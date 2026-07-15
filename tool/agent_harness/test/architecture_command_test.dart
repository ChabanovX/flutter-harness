import 'dart:convert';
import 'dart:io';

import 'package:agent_harness/src/architecture/architecture_checker.dart';
import 'package:agent_harness/src/architecture/violation.dart';
import 'package:agent_harness/src/config/harness_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_project.dart';

void main() {
  test('architecture JSON and baseline include navigation violations', () async {
    final project = TestProject.create();
    addTearDown(project.dispose);
    project.write(
      'lib/features/catalog/presentation/widgets/catalog_link.dart',
      "import 'package:go_router/go_router.dart';\n",
    );

    final failed = await _runArchitectureJson(project);

    expect(failed.exitCode, 1, reason: failed.stderr.toString());
    final failedJson = jsonDecode(failed.stdout.toString()) as Map<String, Object?>;
    final newViolations = failedJson['new_violations']! as List<Object?>;
    expect(
      newViolations.whereType<Map<String, Object?>>().map(
        (item) => item['rule'],
      ),
      contains('router_dependency_outside_router'),
    );

    final config = HarnessConfig.load(project.root);
    final report = ArchitectureChecker(config).check();
    ViolationBaseline.write(
      File(p.join(project.root.path, config.architecture.baselinePath)),
      report.violations,
    );

    final accepted = await _runArchitectureJson(project);

    expect(accepted.exitCode, 0, reason: accepted.stderr.toString());
    final acceptedJson = jsonDecode(accepted.stdout.toString()) as Map<String, Object?>;
    expect(acceptedJson['new_violations'], isEmpty);
    expect(acceptedJson['accepted_violations'], hasLength(1));
  });
}

Future<ProcessResult> _runArchitectureJson(TestProject project) {
  return Process.run(
    Platform.resolvedExecutable,
    [
      'run',
      'bin/agent_harness.dart',
      '--root',
      project.root.path,
      'architecture',
      '--json',
    ],
    workingDirectory: Directory.current.path,
  );
}
