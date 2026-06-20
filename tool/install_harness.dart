import 'dart:io';

const defaultRepositoryUrl = 'https://github.com/ChabanovX/flutter-harness.git';
const defaultSubmodulePath = 'tool/flutter_agentic_harness';
const defaultBranch = 'main';
const analyzerVersion = '10.2.0';

Future<void> main(List<String> arguments) async {
  try {
    final options = InstallOptions.parse(arguments);
    if (options.help) {
      stdout.write(usage);
      return;
    }

    final installer = HarnessInstaller(
      options: options,
      harnessRoot: File.fromUri(Platform.script).absolute.parent.parent,
    );
    await installer.run();
  } on UsageException catch (error) {
    stderr
      ..writeln(error.message)
      ..write(usage);
    exitCode = 64;
  } on InstallException catch (error) {
    stderr.writeln(error.message);
    exitCode = error.exitCode;
  }
}

final class InstallOptions {
  const InstallOptions({
    required this.projectRoot,
    required this.repositoryUrl,
    required this.submodulePath,
    required this.branch,
    required this.force,
    required this.skipPubAdd,
    required this.help,
  });

  factory InstallOptions.parse(List<String> arguments) {
    var projectRoot = Directory.current;
    String? repositoryUrl;
    var submodulePath = defaultSubmodulePath;
    String? branch = defaultBranch;
    var force = false;
    var skipPubAdd = false;
    var help = false;

    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      switch (argument) {
        case '--help' || '-h':
          help = true;
        case '--force':
          force = true;
        case '--skip-pub-add':
          skipPubAdd = true;
        case '--no-branch':
          branch = null;
        case final value when value.startsWith('--project-root='):
          projectRoot = Directory(value.substring('--project-root='.length));
        case '--project-root':
          index += 1;
          _requireValue(arguments, index, '--project-root');
          projectRoot = Directory(arguments[index]);
        case final value when value.startsWith('--repo='):
          repositoryUrl = value.substring('--repo='.length);
        case '--repo':
          index += 1;
          _requireValue(arguments, index, '--repo');
          repositoryUrl = arguments[index];
        case final value when value.startsWith('--path='):
          submodulePath = value.substring('--path='.length);
        case '--path':
          index += 1;
          _requireValue(arguments, index, '--path');
          submodulePath = arguments[index];
        case final value when value.startsWith('--branch='):
          branch = value.substring('--branch='.length);
        case '--branch':
          index += 1;
          _requireValue(arguments, index, '--branch');
          branch = arguments[index];
        default:
          throw UsageException('Unknown argument: $argument');
      }
    }

    if (submodulePath.trim().isEmpty || _isUnsafeRelativePath(submodulePath)) {
      throw const UsageException(
        '--path must be a safe project-relative path.',
      );
    }

    return InstallOptions(
      projectRoot: projectRoot.absolute,
      repositoryUrl: repositoryUrl,
      submodulePath: _toPosix(submodulePath),
      branch: branch?.trim().isEmpty ?? true ? null : branch,
      force: force,
      skipPubAdd: skipPubAdd,
      help: help,
    );
  }

  final Directory projectRoot;
  final String? repositoryUrl;
  final String submodulePath;
  final String? branch;
  final bool force;
  final bool skipPubAdd;
  final bool help;

  static void _requireValue(List<String> arguments, int index, String option) {
    if (index >= arguments.length) {
      throw UsageException('$option requires a value.');
    }
  }
}

final class HarnessInstaller {
  const HarnessInstaller({required this.options, required this.harnessRoot});

  final InstallOptions options;
  final Directory harnessRoot;

  Future<void> run() async {
    final projectRoot = options.projectRoot;
    _validateFlutterProject(projectRoot);
    await _validateGitProject(projectRoot);

    final repositoryUrl = options.repositoryUrl ?? await _inferRepositoryUrl(harnessRoot);
    await _ensureSubmodule(
      projectRoot: projectRoot,
      repositoryUrl: repositoryUrl,
      submodulePath: options.submodulePath,
      branch: options.branch,
    );

    final sourceRoot = Directory(
      _join(projectRoot.path, options.submodulePath),
    );
    _validateSourceRoot(sourceRoot);
    _writeHarnessFiles(projectRoot: projectRoot, sourceRoot: sourceRoot);

    if (!options.skipPubAdd) {
      await _addApplicationDependencies(projectRoot);
    }

    stdout
      ..writeln('Harness installed as submodule at ${options.submodulePath}.')
      ..writeln('Next: dart run tool/harness.dart doctor');
  }

  void _validateFlutterProject(Directory projectRoot) {
    final pubspec = File(_join(projectRoot.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw const InstallException(
        'pubspec.yaml not found. Run this from a Flutter project root or pass '
        '--project-root.',
      );
    }
    final text = pubspec.readAsStringSync();
    if (!RegExp(r'sdk:\s*flutter').hasMatch(text)) {
      throw const InstallException(
        'pubspec.yaml does not look like a Flutter project. Expected a '
        'dependency with sdk: flutter.',
      );
    }
  }

  Future<void> _validateGitProject(Directory projectRoot) async {
    final result = await _capture('git', const [
      'rev-parse',
      '--is-inside-work-tree',
    ], workingDirectory: projectRoot);
    if (result.exitCode != 0 || result.stdout.trim() != 'true') {
      throw const InstallException(
        'The target project must be a Git repository before adding a submodule.',
      );
    }
  }

  Future<String> _inferRepositoryUrl(Directory root) async {
    final result = await _capture('git', const [
      'remote',
      'get-url',
      'origin',
    ], workingDirectory: root);
    final remote = result.stdout.trim();
    if (result.exitCode == 0 && remote.isNotEmpty) return remote;
    return defaultRepositoryUrl;
  }

  Future<void> _ensureSubmodule({
    required Directory projectRoot,
    required String repositoryUrl,
    required String submodulePath,
    required String? branch,
  }) async {
    final target = Directory(_join(projectRoot.path, submodulePath));
    if (target.existsSync()) {
      stdout.writeln('Keeping existing submodule path $submodulePath.');
      return;
    }

    final arguments = [
      'submodule',
      'add',
      if (branch != null) ...['-b', branch],
      repositoryUrl,
      submodulePath,
    ];
    await _run('git', arguments, workingDirectory: projectRoot);
  }

  void _validateSourceRoot(Directory sourceRoot) {
    final requiredFiles = [
      'AGENTS.md',
      '.agent_harness.yaml',
      '.agent_harness/baseline.json',
      'analysis_options.harness.snippet.yaml',
      'tool/agent_harness/pubspec.yaml',
    ];
    for (final path in requiredFiles) {
      if (!File(_join(sourceRoot.path, path)).existsSync()) {
        throw InstallException(
          'Harness submodule at ${options.submodulePath} is incomplete. '
          'Run git submodule update --init --recursive, or remove the path '
          'and rerun the installer.',
        );
      }
    }
  }

  void _writeHarnessFiles({
    required Directory projectRoot,
    required Directory sourceRoot,
  }) {
    _writeFile(
      File(_join(projectRoot.path, 'tool/harness.dart')),
      renderSubmoduleLauncher(options.submodulePath),
    );
    _writeFile(
      File(_join(projectRoot.path, 'AGENTS.md')),
      renderAgentInstructions(
        File(_join(sourceRoot.path, 'AGENTS.md')).readAsStringSync(),
        options.submodulePath,
      ),
    );
    _writeFile(
      File(_join(projectRoot.path, '.agent_harness.yaml')),
      File(_join(sourceRoot.path, '.agent_harness.yaml')).readAsStringSync(),
    );
    _writeFile(
      File(_join(projectRoot.path, '.agent_harness/baseline.json')),
      File(
        _join(sourceRoot.path, '.agent_harness/baseline.json'),
      ).readAsStringSync(),
    );
    _writeAnalysisOptions(
      File(_join(projectRoot.path, 'analysis_options.yaml')),
      renderAnalysisOptions(options.submodulePath),
    );
  }

  void _writeFile(File file, String content) {
    if (file.existsSync()) {
      final current = file.readAsStringSync();
      if (current == content) {
        stdout.writeln('Kept ${_relativeToProject(file)}.');
        return;
      }
      if (!options.force) {
        stdout.writeln(
          'Preserved existing ${_relativeToProject(file)}; pass --force to '
          'overwrite.',
        );
        return;
      }
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    stdout.writeln('Wrote ${_relativeToProject(file)}.');
  }

  void _writeAnalysisOptions(File file, String content) {
    if (file.existsSync()) {
      final current = file.readAsStringSync();
      if (current == content) {
        stdout.writeln('Kept ${_relativeToProject(file)}.');
        return;
      }
      if (!options.force && !isDefaultFlutterAnalysisOptions(current)) {
        stdout.writeln(
          'Preserved existing ${_relativeToProject(file)}; pass --force to '
          'overwrite.',
        );
        return;
      }
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    stdout.writeln('Wrote ${_relativeToProject(file)}.');
  }

  Future<void> _addApplicationDependencies(Directory projectRoot) async {
    await _run('flutter', const [
      'pub',
      'add',
      'flutter_bloc',
      'get_it',
      'logger',
      'intl',
    ], workingDirectory: projectRoot);
    await _run('flutter', const [
      'pub',
      'add',
      'flutter_localizations',
      '--sdk=flutter',
    ], workingDirectory: projectRoot);
    await _run('flutter', const [
      'pub',
      'add',
      '--dev',
      'very_good_analysis:$analyzerVersion',
      'assetify',
      'alchemist',
    ], workingDirectory: projectRoot);
    if (_usesHarnessAnalysisOptions(projectRoot) && _hasPubspecDependency(projectRoot, 'flutter_lints')) {
      await _run('flutter', const [
        'pub',
        'remove',
        'flutter_lints',
      ], workingDirectory: projectRoot);
    }
  }

  String _relativeToProject(File file) {
    final root = _toPosix(options.projectRoot.path);
    final path = _toPosix(file.path);
    if (!path.startsWith('$root/')) return path;
    return path.substring(root.length + 1);
  }
}

bool isDefaultFlutterAnalysisOptions(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  return normalized.contains('include: package:flutter_lints/flutter.yaml') &&
      !normalized.contains('analysis_options.harness.snippet.yaml');
}

bool _usesHarnessAnalysisOptions(Directory projectRoot) {
  final analysisOptions = File(
    _join(projectRoot.path, 'analysis_options.yaml'),
  );
  if (!analysisOptions.existsSync()) return false;
  return analysisOptions.readAsStringSync().contains(
    'analysis_options.harness.snippet.yaml',
  );
}

bool _hasPubspecDependency(Directory projectRoot, String dependency) {
  final pubspec = File(_join(projectRoot.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  return RegExp(
    '^  ${RegExp.escape(dependency)}:',
    multiLine: true,
  ).hasMatch(pubspec.readAsStringSync());
}

String renderSubmoduleLauncher(String submodulePath) {
  final path = _toPosix(submodulePath);
  return _withoutLeadingNewline('''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final launcher = File.fromUri(Platform.script).absolute;
  final projectRoot = launcher.parent.parent.absolute;
  final harnessRoot = Directory(
    '\${projectRoot.path}\${Platform.pathSeparator}${_platformPathLiteral(path)}',
  );
  final toolDirectory = Directory(
    '\${harnessRoot.path}\${Platform.pathSeparator}tool'
    '\${Platform.pathSeparator}agent_harness',
  );
  final pubspec = File(
    '\${toolDirectory.path}\${Platform.pathSeparator}pubspec.yaml',
  );
  final packageConfig = File(
    '\${toolDirectory.path}\${Platform.pathSeparator}.dart_tool'
    '\${Platform.pathSeparator}package_config.json',
  );

  if (!pubspec.existsSync()) {
    stderr.writeln(
      'Harness package not found at \${toolDirectory.path}. '
      'Run git submodule update --init --recursive.',
    );
    exitCode = 66;
    return;
  }

  final needsPubGet =
      !packageConfig.existsSync() || pubspec.lastModifiedSync().isAfter(packageConfig.lastModifiedSync());
  if (needsPubGet) {
    stdout.writeln('Preparing local agent harness dependencies...');
    final pubGet = await Process.start(
      Platform.resolvedExecutable,
      const ['pub', 'get'],
      workingDirectory: toolDirectory.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    final pubGetCode = await pubGet.exitCode;
    if (pubGetCode != 0) {
      exitCode = pubGetCode;
      return;
    }
  }

  final hasExplicitRoot = arguments.any(
    (argument) => argument == '--root' || argument.startsWith('--root='),
  );
  final forwarded = <String>[
    'run',
    'bin/agent_harness.dart',
    if (!hasExplicitRoot) ...['--root', projectRoot.path],
    ...arguments,
  ];
  final process = await Process.start(
    Platform.resolvedExecutable,
    forwarded,
    workingDirectory: toolDirectory.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  exitCode = await process.exitCode;
}
''');
}

String renderAgentInstructions(String source, String submodulePath) {
  final docsPath = '${_toPosix(submodulePath)}/docs/architecture/overview.md';
  return source.replaceAll('docs/architecture/overview.md', docsPath);
}

String renderAnalysisOptions(String submodulePath) {
  final path = _toPosix(submodulePath);
  return _withoutLeadingNewline('''
include:
  - $path/analysis_options.harness.snippet.yaml

analyzer:
  exclude:
    - $path/**
''');
}

String _withoutLeadingNewline(String value) {
  if (value.startsWith('\n')) return value.substring(1);
  return value;
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
}) async {
  stdout.writeln(r'$ ' + [executable, ...arguments].join(' '));
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw InstallException(
      'Command failed with exit code $code: $executable ${arguments.join(' ')}',
      exitCode: code,
    );
  }
}

Future<({int exitCode, String stdout})> _capture(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    runInShell: Platform.isWindows,
  );
  return (exitCode: result.exitCode, stdout: result.stdout.toString());
}

String _join(String left, String right) {
  final separator = Platform.pathSeparator;
  return [
    left,
    ...right.split('/'),
  ].where((part) => part.isNotEmpty).join(separator);
}

String _toPosix(String path) => path.replaceAll(r'\', '/');

String _platformPathLiteral(String posixPath) {
  return posixPath.split('/').join(r'${Platform.pathSeparator}');
}

bool _isUnsafeRelativePath(String path) {
  final normalized = _toPosix(path.trim());
  return normalized.startsWith('/') ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      normalized.contains('/../');
}

final class UsageException implements Exception {
  const UsageException(this.message);

  final String message;
}

final class InstallException implements Exception {
  const InstallException(this.message, {this.exitCode = 1});

  final String message;
  final int exitCode;
}

const usage =
    '''
Install Flutter Agentic Harness into an existing Flutter Git repository.

Usage:
  dart /path/to/flutter_agentic_harness/tool/install_harness.dart [options]

Options:
  --project-root <path>  Target Flutter project root. Defaults to cwd.
  --repo <url>           Harness Git URL. Defaults to this repo's origin.
  --path <path>          Submodule path. Defaults to $defaultSubmodulePath.
  --branch <name>        Submodule branch. Defaults to $defaultBranch.
  --no-branch            Add the submodule without a branch option.
  --force                Overwrite harness-owned files in the target project.
  --skip-pub-add         Do not run flutter pub add commands.
  -h, --help             Show this help.
''';
