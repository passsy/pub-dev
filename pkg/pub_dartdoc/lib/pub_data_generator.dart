// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: deprecated_export_use

import 'dart:convert' as convert;

import 'package:analyzer/file_system/file_system.dart';
import 'package:dartdoc/dartdoc.dart';
// ignore: implementation_imports
import 'package:dartdoc/src/model/inheritable.dart';
// ignore: implementation_imports
import 'package:dartdoc/src/model/model_element.dart';
import 'package:path/path.dart' as p;

import 'package:pub_dartdoc_data/pub_dartdoc_data.dart';

const fileName = 'pub-data.json';

/// Generates `pub-data.json` in the output directory, containing the extracted
/// [PubDartdocData] instance.
class PubDataGenerator {
  final String _inputDirectory;
  final ResourceProvider _resourceProvider;

  PubDataGenerator(this._inputDirectory, this._resourceProvider);

  void generate(PackageGraph packageGraph, String outputDirectoryPath) {
    final modelElements = packageGraph.allCanonicalModelElements
        .where((elem) => elem.isPublic)
        .where((elem) => p.isWithin(_inputDirectory, elem.sourceFileName))
        .where((elem) {
      if (elem is Inheritable) {
        // remove inherited items from dart:* libraries
        final inheritedFrom = elem.overriddenElement?.fullyQualifiedName;
        final fromDartLibs =
            inheritedFrom != null && inheritedFrom.startsWith('dart:');
        return !fromDartLibs;
      } else {
        return true;
      }
    }).toList();

    final apiMap = <String, ApiElement>{};
    void addElement(ModelElement elem) {
      final isReferenced =
          elem.kind == Kind.library || elem.kind == Kind.class_;
      final fqnParts = elem.fullyQualifiedName.split('.');
      final name = fqnParts.removeLast();
      final parent = fqnParts.isEmpty ? null : fqnParts.join('.');
      apiMap.putIfAbsent(
          elem.fullyQualifiedName,
          () => ApiElement(
                name: name,
                kind: elem.kind.toString(),
                parent: parent,
                // TODO: decide if keeping the source reference is worth it
                // We could probably store it more efficiently by not repeating
                // the filename every time.
                // source: p.relative(elem.sourceFileName, from: _inputDirectory),
                source: null,
                href: isReferenced
                    ? _trimToNull(elem.href
                        ?.replaceAll('%%__HTMLBASE_dartdoc_internal__%%', ''))
                    : null,
                documentation: _trimToNull(elem.documentation),
              ));
      if (elem.enclosingElement is ModelElement) {
        addElement(elem.enclosingElement as ModelElement);
      }
    }

    modelElements.forEach(addElement);

    final apiElements = apiMap.values.toList();
    apiElements.sort((a, b) {
      if (a.parent == null && b.parent != null) return -1;
      if (a.parent != null && b.parent == null) return 1;
      if (a.parent != b.parent) {
        // At this point neither parent can be null.
        assert(a.parent != null);
        assert(b.parent != null);
        return a.parent!.compareTo(b.parent!);
      }
      return a.name.compareTo(b.name);
    });

    final coverage = _calculateCoverage(apiElements);

    if (coverage.documented > 1000) {
      // Too much content, removing the documentation from everything except
      // libraries and classes.
      apiElements
          .where((e) => e.kind != 'library' && e.kind != 'class')
          .forEach((e) => e.documentation = null);
    }

    final extract =
        PubDartdocData(coverage: coverage, apiElements: apiElements);

    final fileName = 'pub-data.json';
    _resourceProvider
        .getFile(p.join(outputDirectoryPath, fileName))
        .writeAsStringSync(convert.json.encode(extract.toJson()));
  }

  // Inherited member, should not show up in pub-data.json
  @override
  String toString() => '';
}

String? _trimToNull(String? text) {
  text = text?.trim();
  return (text != null && text.isEmpty) ? null : text;
}

/// Calculate coverage for the extracted API elements.
Coverage _calculateCoverage(List<ApiElement> apiElements) {
  final total = apiElements.length;

  final documented = apiElements
      .where((elem) =>
          elem.documentation != null &&
          elem.documentation!.isNotEmpty &&
          elem.documentation!.trim().length >= 5)
      .length;

  return Coverage(total: total, documented: documented);
}
