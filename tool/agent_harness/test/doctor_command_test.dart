import 'package:agent_harness/src/cli/doctor_command.dart';
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  test('recognizes copied harness layout', () {
    final project = TestProject.create();
    addTearDown(project.dispose);
    project.write('tool/harness.dart', 'void main() {}\n');
    project.write('tool/agent_harness/pubspec.yaml', 'name: agent_harness\n');

    expect(hasHarnessInstallation(project.root), isTrue);
  });

  test('recognizes submodule harness layout', () {
    final project = TestProject.create();
    addTearDown(project.dispose);
    project.write('tool/harness.dart', 'void main() {}\n');
    project.write(
      'tool/flutter_agentic_harness/tool/agent_harness/pubspec.yaml',
      'name: agent_harness\n',
    );

    expect(hasHarnessInstallation(project.root), isTrue);
  });
}
