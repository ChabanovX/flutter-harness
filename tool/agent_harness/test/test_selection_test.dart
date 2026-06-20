import 'package:agent_harness/src/config/harness_config.dart';
import 'package:agent_harness/src/process/git_changes.dart';
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  late TestProject project;
  late HarnessConfig config;

  setUp(() {
    project = TestProject.create();
    project.createDirectory('test/features/catalog');
    config = HarnessConfig.load(project.root);
  });

  tearDown(() => project.dispose());

  test('selects the changed feature tests', () {
    final selection = TestSelection.fromChanges(
      config: config,
      changes: const GitChanges(
        available: true,
        files: ['lib/features/catalog/presentation/catalog_page.dart'],
      ),
    );

    expect(selection.runAll, isFalse);
    expect(selection.skip, isFalse);
    expect(selection.paths, ['test/features/catalog']);
  });

  test('runs all tests for shared changes', () {
    final selection = TestSelection.fromChanges(
      config: config,
      changes: const GitChanges(
        available: true,
        files: ['lib/core/network/api_client.dart'],
      ),
    );

    expect(selection.runAll, isTrue);
    expect(selection.skip, isFalse);
  });

  test('skips tests for documentation-only changes', () {
    final selection = TestSelection.fromChanges(
      config: config,
      changes: const GitChanges(
        available: true,
        files: ['docs/architecture/overview.md'],
      ),
    );

    expect(selection.skip, isTrue);
  });

  test('runs goldens for presentation and design changes only', () {
    final presentation = GoldenSelection.fromChanges(
      config: config,
      changes: const GitChanges(
        available: true,
        files: ['lib/features/catalog/presentation/catalog_page.dart'],
      ),
    );
    expect(presentation.run, isTrue);

    final design = GoldenSelection.fromChanges(
      config: config,
      changes: const GitChanges(
        available: true,
        files: ['lib/core/design_system/tokens/app_colors.dart'],
      ),
    );
    expect(design.run, isTrue);

    final domain = GoldenSelection.fromChanges(
      config: config,
      changes: const GitChanges(
        available: true,
        files: ['lib/features/catalog/domain/catalog_item.dart'],
      ),
    );
    expect(domain.run, isFalse);
  });

  test('uses fallback policy when golden changed-scope metadata is unavailable', () {
    final selection = GoldenSelection.fromChanges(
      config: config,
      changes: const GitChanges(available: false, files: []),
    );

    expect(selection.run, isTrue);
  });
}
