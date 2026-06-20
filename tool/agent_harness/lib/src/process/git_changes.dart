import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/harness_config.dart';
import '../util/files.dart';
import 'command_executor.dart';

final class GitChanges {
  const GitChanges({required this.files, required this.available});

  final List<String> files;
  final bool available;

  static Future<GitChanges> collect({
    required CommandExecutor executor,
    required String base,
  }) async {
    late final ProcessResult inside;
    try {
      inside = await executor.capture(
        'git',
        const ['rev-parse', '--is-inside-work-tree'],
      );
    } on ProcessException {
      return const GitChanges(files: [], available: false);
    }
    if (inside.exitCode != 0 || inside.stdout.toString().trim() != 'true') {
      return const GitChanges(files: [], available: false);
    }

    final changed = <String>{};
    await _addOutput(
      changed,
      executor.capture(
        'git',
        const ['diff', '--name-only', '--diff-filter=ACDMRT', 'HEAD'],
      ),
    );
    await _addOutput(
      changed,
      executor.capture(
        'git',
        const ['ls-files', '--others', '--exclude-standard'],
      ),
    );

    final baseExists = await executor.capture(
      'git',
      ['rev-parse', '--verify', '--quiet', base],
    );
    if (baseExists.exitCode != 0) {
      // A partial diff can silently skip tests for committed branch changes.
      // Mark selection unavailable so the configured safe fallback is used.
      final files = changed.toList(growable: false)..sort();
      return GitChanges(files: files, available: false);
    }

    await _addOutput(
      changed,
      executor.capture(
        'git',
        ['diff', '--name-only', '--diff-filter=ACDMRT', '$base...HEAD'],
      ),
    );

    final files = changed.toList(growable: false)..sort();
    return GitChanges(files: files, available: true);
  }

  static Future<void> _addOutput(
    Set<String> target,
    Future<ProcessResult> resultFuture,
  ) async {
    late final ProcessResult result;
    try {
      result = await resultFuture;
    } on ProcessException {
      return;
    }
    if (result.exitCode != 0) return;
    final lines = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((line) => toPosixPath(line.trim()))
        .where((line) => line.isNotEmpty);
    target.addAll(lines);
  }
}

final class TestSelection {
  const TestSelection({
    required this.runAll,
    required this.skip,
    required this.paths,
    required this.reason,
  });

  final bool runAll;
  final bool skip;
  final List<String> paths;
  final String reason;

  static TestSelection fromChanges({
    required HarnessConfig config,
    required GitChanges changes,
  }) {
    if (!changes.available) {
      return TestSelection(
        runAll: config.verification.fallbackToAllTests,
        skip: !config.verification.fallbackToAllTests,
        paths: const [],
        reason: 'Git metadata is unavailable.',
      );
    }

    if (changes.files.isEmpty) {
      return const TestSelection(
        runAll: false,
        skip: true,
        paths: [],
        reason: 'No changed files detected.',
      );
    }

    final nonDocumentation = changes.files.where((path) => !isDocumentationPath(path)).toList(growable: false);
    if (nonDocumentation.isEmpty) {
      return const TestSelection(
        runAll: false,
        skip: true,
        paths: [],
        reason: 'Only documentation changed.',
      );
    }

    final featureRoot = toPosixPath(config.project.featureRoot);
    final selected = <String>{};
    var needsAll = false;

    for (final changed in nonDocumentation) {
      final path = toPosixPath(changed);
      if (path.startsWith('test/') || path.startsWith('integration_test/')) {
        if (File(p.join(config.root.path, path)).existsSync()) {
          selected.add(path);
        }
        continue;
      }

      if (path.startsWith('$featureRoot/')) {
        final remainder = p.posix.relative(path, from: featureRoot);
        final segments = p.posix.split(remainder);
        if (segments.isNotEmpty) {
          final testDirectory = 'test/features/${segments.first}';
          if (Directory(p.join(config.root.path, testDirectory)).existsSync()) {
            selected.add(testDirectory);
          } else {
            needsAll = config.verification.fallbackToAllTests;
          }
          continue;
        }
      }

      if (path.startsWith('tool/agent_harness/')) {
        needsAll = true;
        continue;
      }

      if (path == 'pubspec.yaml' ||
          path == 'pubspec.lock' ||
          path == '.agent_harness.yaml' ||
          path.startsWith('${config.project.appRoot}/') ||
          path.startsWith('${config.project.coreRoot}/') ||
          path.startsWith('${config.project.sharedRoot}/') ||
          path.startsWith('test/support/')) {
        needsAll = true;
        continue;
      }

      if (path.endsWith('.dart')) needsAll = true;
    }

    if (needsAll) {
      return const TestSelection(
        runAll: true,
        skip: false,
        paths: [],
        reason:
            'A shared, app-level, dependency, tooling, or unclassified '
            'Dart file changed.',
      );
    }

    if (selected.isEmpty) {
      return TestSelection(
        runAll: config.verification.fallbackToAllTests,
        skip: !config.verification.fallbackToAllTests,
        paths: const [],
        reason: 'No affected test directory could be selected.',
      );
    }

    final paths = selected.toList(growable: false)..sort();
    return TestSelection(
      runAll: false,
      skip: false,
      paths: paths,
      reason: 'Selected tests from changed feature paths.',
    );
  }
}
