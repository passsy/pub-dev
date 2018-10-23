// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';

import 'packages_overrides.dart';
import 'utils.dart';

final Logger _logger = new Logger('pub.scheduler');

/// Interface for task execution.
// ignore: one_member_abstracts
abstract class TaskRunner {
  /// Run the task.
  Future runTask(Task task);
}

// ignore: one_member_abstracts
abstract class TaskSource {
  /// Returns a stream of currently available tasks at the time of the call.
  /// Some task sources (e.g. Datastore-polling sources) may never close.
  Stream<Task> startStreaming();
}

/// Tasks coming from through the isolate's receivePort, originating from a
/// HTTP handler that received a ping after a new upload.
class ManualTriggerTaskSource implements TaskSource {
  final Stream<Task> _taskReceivePort;
  ManualTriggerTaskSource(this._taskReceivePort);

  @override
  Stream<Task> startStreaming() => _taskReceivePort;
}

/// Schedules and executes tasks.
///
/// The execution of the tasks are prioritized in the order of the task sources:
/// the ones from a lower-index source will be selected earlier than the ones
/// from a high-index source.
///
/// Some task sources (e.g. Datastore-polling sources) may never close.
class TaskScheduler {
  final TaskRunner taskRunner;
  final List<TaskSource> sources;
  final bool randomize;
  final LastNTracker<String> _statusTracker = new LastNTracker();
  final LastNTracker<num> _latencyTracker = new LastNTracker();
  List<List<Task>> _queues;
  bool _needsShuffle = false;

  TaskScheduler(this.taskRunner, this.sources, {this.randomize = false}) {
    _queues = new List<List<Task>>.generate(sources.length, (i) => <Task>[]);
  }

  Future run() async {
    Future runTask(Task task) async {
      final Stopwatch sw = new Stopwatch()..start();
      try {
        if (redirectPackagePages.containsKey(task.package)) {
          return;
        }
        await taskRunner.runTask(task);
        _statusTracker.add('normal');
      } catch (e, st) {
        _logger.severe('Error processing task: $task', e, st);
        _statusTracker.add('error');
      }
      _latencyTracker.add(sw.elapsedMilliseconds);
    }

    int liveSubscriptions = sources.length;
    for (int i = 0; i < sources.length; i++) {
      sources[i].startStreaming().listen(
        (task) {
          _queues[i].add(task);
          if (randomize) {
            _needsShuffle = true;
          }
        },
        onDone: () {
          liveSubscriptions--;
        },
      );
    }

    while (liveSubscriptions > 0) {
      _shuffleQueues();
      final task = _pickFirstTask();

      if (task == null) {
        await new Future.delayed(const Duration(seconds: 5));
        continue;
      }

      await runTask(task);
    }
  }

  void _shuffleQueues() {
    if (_needsShuffle) {
      for (List<Task> queue in _queues) {
        queue.shuffle();
      }
    }
    _needsShuffle = false;
  }

  Task _pickFirstTask() {
    for (List<Task> queue in _queues) {
      if (queue.isEmpty) continue;
      return queue.removeLast();
    }
    return null;
  }

  Map stats() {
    final int pendingCount = _queues.fold<int>(0, (sum, q) => sum + q.length);
    final Map<String, dynamic> stats = <String, dynamic>{
      'pending': pendingCount,
      'status': _statusTracker.toCounts(),
    };
    final double avgMillis = _latencyTracker.average;
    if (avgMillis > 0.0) {
      final double tph = 60 * 60 * 1000.0 / avgMillis;
      stats['taskPerHour'] = tph;
      final remaining =
          new Duration(milliseconds: (pendingCount * avgMillis).round());
      stats['remaining'] = formatDuration(remaining);
    }
    return stats;
  }
}

/// A task for a given package and version.
class Task {
  final String package;
  final String version;
  final DateTime updated;

  Task(this.package, this.version, this.updated);

  Task.now(this.package, this.version) : updated = new DateTime.now();

  @override
  String toString() => '$package $version';
}
