import 'package:agent_harness/src/cli/verify_command.dart';
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  test('detects when no test directories exist', () {
    final project = TestProject.create();
    addTearDown(project.dispose);

    expect(hasAnyTestDirectory(project.root), isFalse);
  });

  test('detects normal and integration test directories', () {
    final project = TestProject.create();
    addTearDown(project.dispose);
    project.createDirectory('integration_test');

    expect(hasAnyTestDirectory(project.root), isTrue);
  });
}
