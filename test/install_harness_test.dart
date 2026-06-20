import 'package:test/test.dart';

import '../tool/install_harness.dart' as installer;

void main() {
  test('renders a launcher that targets the harness submodule package', () {
    final launcher = installer.renderSubmoduleLauncher(
      installer.defaultSubmodulePath,
    );

    expect(launcher, contains('tool'));
    expect(launcher, contains('flutter_agentic_harness'));
    expect(launcher, contains('agent_harness'));
    expect(launcher, contains('Run git submodule update --init --recursive.'));
  });

  test('rewrites AGENTS documentation paths to the submodule', () {
    final rendered = installer.renderAgentInstructions(
      'Read `docs/architecture/overview.md` first.',
      installer.defaultSubmodulePath,
    );

    expect(
      rendered,
      contains('`tool/flutter_agentic_harness/docs/architecture/overview.md`'),
    );
  });

  test('renders analyzer options that include and exclude the submodule', () {
    final options = installer.renderAnalysisOptions(
      installer.defaultSubmodulePath,
    );

    expect(
      options,
      contains(
        'tool/flutter_agentic_harness/analysis_options.harness.snippet.yaml',
      ),
    );
    expect(options, contains('tool/flutter_agentic_harness/**'));
  });
}
