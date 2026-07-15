import 'dart:io';

import 'package:test/test.dart';

import '../tool/install_harness.dart' as installer;

void main() {
  test(
    'installs navigation and localization dependencies in one Pub transaction',
    () {
      expect(installer.applicationDependencyArguments, [
        'pub',
        'add',
        'flutter_bloc',
        'go_router',
        'get_it',
        'logger',
        'intl',
        'flutter_localizations:{sdk: flutter}',
      ]);
    },
  );

  test('renders a launcher that targets the harness submodule package', () {
    final launcher = installer.renderSubmoduleLauncher(
      installer.defaultSubmodulePath,
    );

    expect(launcher, startsWith("import 'dart:io';"));
    expect(launcher, contains('tool'));
    expect(launcher, contains('flutter_agentic_harness'));
    expect(launcher, contains('agent_harness'));
    expect(launcher, contains('Run git submodule update --init --recursive.'));
  });

  test('renders a launcher accepted by dart format', () async {
    final directory = await Directory.systemTemp.createTemp(
      'harness_launcher_test_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    File('${directory.path}/pubspec.yaml').writeAsStringSync('''
name: launcher_format_fixture
publish_to: none

environment:
  sdk: ">=3.11.0 <4.0.0"
''');
    File('${directory.path}/analysis_options.yaml').writeAsStringSync('''
formatter:
  page_width: 120
  trailing_commas: preserve
''');
    final pubGet = await Process.run(Platform.resolvedExecutable, const [
      'pub',
      'get',
    ], workingDirectory: directory.path);
    expect(pubGet.exitCode, 0, reason: pubGet.stderr.toString());

    final toolDirectory = Directory('${directory.path}/tool')..createSync(recursive: true);
    File('${toolDirectory.path}/harness.dart').writeAsStringSync(
      installer.renderSubmoduleLauncher(installer.defaultSubmodulePath),
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      'tool/harness.dart',
    ], workingDirectory: directory.path);

    expect(result.exitCode, 0, reason: result.stdout.toString());
  });

  test('rewrites AGENTS documentation paths to the submodule', () {
    final rendered = installer.renderAgentInstructions(
      'Read `docs/architecture/overview.md` and '
      '`docs/architecture/commenting.md`, then '
      '`docs/architecture/navigation.md` first.',
      installer.defaultSubmodulePath,
    );

    expect(
      rendered,
      contains('`tool/flutter_agentic_harness/docs/architecture/overview.md`'),
    );
    expect(
      rendered,
      contains(
        '`tool/flutter_agentic_harness/docs/architecture/commenting.md`',
      ),
    );
    expect(
      rendered,
      contains(
        '`tool/flutter_agentic_harness/docs/architecture/navigation.md`',
      ),
    );
  });

  test('renders analyzer options that include and exclude the submodule', () {
    final options = installer.renderAnalysisOptions(
      installer.defaultSubmodulePath,
    );

    expect(options, startsWith('include:'));
    expect(
      options,
      contains(
        'tool/flutter_agentic_harness/analysis_options.harness.snippet.yaml',
      ),
    );
    expect(options, contains('tool/flutter_agentic_harness/**'));
  });

  test('detects the default Flutter analyzer options file', () {
    expect(
      installer.isDefaultFlutterAnalysisOptions('''
include: package:flutter_lints/flutter.yaml

linter:
  rules:
'''),
      isTrue,
    );
    expect(
      installer.isDefaultFlutterAnalysisOptions('''
include:
  - tool/flutter_agentic_harness/analysis_options.harness.snippet.yaml
'''),
      isFalse,
    );
    expect(
      installer.isDefaultFlutterAnalysisOptions('''
include: package:very_good_analysis/analysis_options.yaml
'''),
      isFalse,
    );
  });

  test('installs Codex assets through the full harness installer', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'harness_install_project_',
    );
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    File(_join(projectRoot, 'pubspec.yaml')).writeAsStringSync('''
name: harness_install_fixture
publish_to: none

environment:
  sdk: ">=3.11.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
''');
    final gitInit = await Process.run(
      'git',
      const ['init'],
      workingDirectory: projectRoot.path,
    );
    expect(gitInit.exitCode, 0, reason: gitInit.stderr.toString());

    final submoduleRoot = Directory(
      _join(projectRoot, installer.defaultSubmodulePath),
    )..createSync(recursive: true);
    _copyHarnessInstallFixture(
      sourceRoot: Directory.current,
      targetRoot: submoduleRoot,
    );

    await installer.HarnessInstaller(
      options: installer.InstallOptions(
        projectRoot: projectRoot,
        repositoryUrl: 'unused',
        submodulePath: installer.defaultSubmodulePath,
        branch: installer.defaultBranch,
        force: false,
        skipPubAdd: true,
        help: false,
      ),
      harnessRoot: Directory.current,
    ).run();

    for (final path in installer.harnessCodexRequiredFiles) {
      expect(
        File(_join(projectRoot, path)).readAsStringSync(),
        File(_join(submoduleRoot, path)).readAsStringSync(),
      );
    }
  });

  test('installs and refreshes harness-managed Codex assets', () async {
    final sourceRoot = await Directory.systemTemp.createTemp(
      'harness_codex_source_',
    );
    final projectRoot = await Directory.systemTemp.createTemp(
      'harness_codex_project_',
    );
    addTearDown(() => sourceRoot.deleteSync(recursive: true));
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    _writeCodexAssetFixture(sourceRoot, version: 'v1');

    installer.installHarnessCodexAssets(
      projectRoot: projectRoot,
      sourceRoot: sourceRoot,
      force: false,
    );

    for (final path in installer.harnessCodexRequiredFiles) {
      expect(File(_join(projectRoot, path)).readAsStringSync(), contains('v1'));
    }

    _writeCodexAssetFixture(sourceRoot, version: 'v2');
    installer.installHarnessCodexAssets(
      projectRoot: projectRoot,
      sourceRoot: sourceRoot,
      force: false,
    );

    for (final path in installer.harnessCodexRequiredFiles) {
      expect(File(_join(projectRoot, path)).readAsStringSync(), contains('v2'));
    }
  });

  test('installs managed Codex assets discovered below managed roots', () async {
    final sourceRoot = await Directory.systemTemp.createTemp(
      'harness_codex_source_',
    );
    final projectRoot = await Directory.systemTemp.createTemp(
      'harness_codex_project_',
    );
    addTearDown(() => sourceRoot.deleteSync(recursive: true));
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    _writeCodexAssetFixture(sourceRoot, version: 'managed');
    const discoveredPath = '.agents/skills/harness-review/references/future-role.md';
    final discoveredSource = File(_join(sourceRoot, discoveredPath));
    discoveredSource.parent.createSync(recursive: true);
    discoveredSource.writeAsStringSync(
      '<!-- ${installer.codexAssetManagedMarker} -->\nfuture role\n',
    );

    installer.installHarnessCodexAssets(
      projectRoot: projectRoot,
      sourceRoot: sourceRoot,
      force: false,
    );

    expect(
      File(_join(projectRoot, discoveredPath)).readAsStringSync(),
      discoveredSource.readAsStringSync(),
    );
  });

  test('rejects an unmarked Codex asset discovered below managed roots', () async {
    final sourceRoot = await Directory.systemTemp.createTemp(
      'harness_codex_source_',
    );
    final projectRoot = await Directory.systemTemp.createTemp(
      'harness_codex_project_',
    );
    addTearDown(() => sourceRoot.deleteSync(recursive: true));
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    _writeCodexAssetFixture(sourceRoot, version: 'managed');
    const unmarkedPath = '.agents/skills/harness-review/references/unmanaged.md';
    final unmarkedSource = File(_join(sourceRoot, unmarkedPath));
    unmarkedSource.parent.createSync(recursive: true);
    unmarkedSource.writeAsStringSync('unmanaged content\n');

    expect(
      () => installer.installHarnessCodexAssets(
        projectRoot: projectRoot,
        sourceRoot: sourceRoot,
        force: false,
      ),
      throwsA(
        isA<installer.InstallException>().having(
          (error) => error.message,
          'message',
          contains(unmarkedPath),
        ),
      ),
    );
  });

  test('preserves unmanaged Codex asset collisions unless forced', () async {
    final sourceRoot = await Directory.systemTemp.createTemp(
      'harness_codex_source_',
    );
    final projectRoot = await Directory.systemTemp.createTemp(
      'harness_codex_project_',
    );
    addTearDown(() => sourceRoot.deleteSync(recursive: true));
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    _writeCodexAssetFixture(sourceRoot, version: 'managed');

    final collisionPath = installer.harnessCodexRequiredFiles.first;
    final collision = File(_join(projectRoot, collisionPath));
    collision.parent.createSync(recursive: true);
    collision.writeAsStringSync('user-owned content\n');

    installer.installHarnessCodexAssets(
      projectRoot: projectRoot,
      sourceRoot: sourceRoot,
      force: false,
    );
    expect(collision.readAsStringSync(), 'user-owned content\n');

    installer.installHarnessCodexAssets(
      projectRoot: projectRoot,
      sourceRoot: sourceRoot,
      force: true,
    );
    expect(collision.readAsStringSync(), contains('managed'));
    expect(
      collision.readAsStringSync(),
      contains(installer.codexAssetManagedMarker),
    );
  });
}

void _writeCodexAssetFixture(Directory sourceRoot, {required String version}) {
  for (final path in installer.harnessCodexRequiredFiles) {
    final file = File(_join(sourceRoot, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '# ${installer.codexAssetManagedMarker}\n$version $path\n',
    );
  }
}

void _copyHarnessInstallFixture({
  required Directory sourceRoot,
  required Directory targetRoot,
}) {
  const baseFiles = [
    'AGENTS.md',
    '.agent_harness.yaml',
    '.agent_harness/baseline.json',
    'analysis_options.harness.snippet.yaml',
    'tool/agent_harness/pubspec.yaml',
  ];
  for (final path in [...baseFiles, ...installer.harnessCodexRequiredFiles]) {
    final target = File(_join(targetRoot, path));
    target.parent.createSync(recursive: true);
    File(_join(sourceRoot, path)).copySync(target.path);
  }
}

String _join(Directory root, String relativePath) {
  return [
    root.path,
    ...relativePath.split('/'),
  ].join(Platform.pathSeparator);
}
