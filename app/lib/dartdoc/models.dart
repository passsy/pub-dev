// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: annotate_overrides

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:json_annotation/json_annotation.dart';

import '../shared/versions.dart' as versions;

import 'storage_path.dart' as storage_path;

part 'models.g.dart';

@JsonSerializable()
class DartdocEntry {
  final String uuid;
  final String packageName;
  final String packageVersion;
  final bool isLatest;
  final bool isObsolete;
  final bool usesFlutter;
  final String runtimeVersion;
  final String sdkVersion;
  final String dartdocVersion;
  final String flutterVersion;
  final String customizationVersion;
  final DateTime timestamp;
  final bool depsResolved;
  final bool hasContent;
  final int archiveSize;
  final int totalSize;

  DartdocEntry({
    @required this.uuid,
    @required this.packageName,
    @required this.packageVersion,
    @required this.isLatest,
    @required this.isObsolete,
    @required this.usesFlutter,
    @required this.runtimeVersion,
    @required this.sdkVersion,
    @required this.dartdocVersion,
    @required this.flutterVersion,
    @required this.customizationVersion,
    @required this.timestamp,
    @required this.depsResolved,
    @required this.hasContent,
    @required this.archiveSize,
    @required this.totalSize,
  });

  factory DartdocEntry.fromJson(Map<String, dynamic> json) =>
      _$DartdocEntryFromJson(json);

  factory DartdocEntry.fromBytes(List<int> bytes) => new DartdocEntry.fromJson(
      json.decode(utf8.decode(bytes)) as Map<String, dynamic>);

  static Future<DartdocEntry> fromStream(Stream<List<int>> stream) async {
    final bytes =
        await stream.fold<List<int>>([], (sum, list) => sum..addAll(list));
    return new DartdocEntry.fromBytes(bytes);
  }

  Map<String, dynamic> toJson() => _$DartdocEntryToJson(this);

  bool get isServing => versions.shouldServeDartdoc(runtimeVersion);

  /// The path of the status while the upload is in progress
  String get inProgressPrefix =>
      storage_path.inProgressPrefix(packageName, packageVersion);

  /// The path of the particular JSON status while upload is in progress
  String get inProgressObjectName =>
      storage_path.inProgressObjectName(packageName, packageVersion, uuid);

  /// The path prefix where all of the entry JSON files are stored.
  String get entryPrefix =>
      storage_path.entryPrefix(packageName, packageVersion);

  /// The path of the particular JSON entry after the upload was completed.
  String get entryObjectName =>
      storage_path.entryObjectName(packageName, packageVersion, uuid);

  /// The path prefix where the content of this instance is stored.
  String get contentPrefix =>
      storage_path.contentPrefix(packageName, packageVersion, uuid);

  String objectName(String relativePath) {
    final isShared = storage_path.isSharedAsset(relativePath);
    if (isShared) {
      return storage_path.sharedAssetObjectName(dartdocVersion, relativePath);
    } else {
      return storage_path.contentObjectName(
          packageName, packageVersion, uuid, relativePath);
    }
  }

  List<int> asBytes() => utf8.encode(json.encode(this.toJson()));

  bool isRegression(DartdocEntry oldEntry) {
    if (oldEntry == null) {
      // Old entry does not exists, new entry wins.
      return false;
    }
    if (oldEntry.runtimeVersion != runtimeVersion) {
      // Different versions - not considered as a regression.
      return false;
    }
    if (!oldEntry.hasContent) {
      // The old entry had no content, the new should be better.
      return false;
    }
    if (hasContent) {
      // Having new content wins.
      return false;
    }
    // Older entry seems to be better.
    return true;
  }
}

@JsonSerializable()
class FileInfo {
  final DateTime lastModified;
  final String etag;

  FileInfo({@required this.lastModified, @required this.etag});

  factory FileInfo.fromJson(Map<String, dynamic> json) =>
      _$FileInfoFromJson(json);

  factory FileInfo.fromBytes(List<int> bytes) => new FileInfo.fromJson(
      json.decode(utf8.decode(bytes)) as Map<String, dynamic>);

  List<int> asBytes() => utf8.encode(json.encode(this.toJson()));

  Map<String, dynamic> toJson() => _$FileInfoToJson(this);
}
