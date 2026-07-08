import 'dart:io';

import 'package:test/test.dart';

import '../tool/install_harness.dart' as installer;

void main() {
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

    final toolDirectory = Directory('${directory.path}/tool')
      ..createSync(recursive: true);
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
      '`docs/architecture/commenting.md` first.',
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
}
