import 'dart:io';

import 'package:path/path.dart' as p;

final class TestProject {
  TestProject._(this.root);

  final Directory root;

  static TestProject create({String? config}) {
    final root = Directory.systemTemp.createTempSync('agent_harness_test_');
    final project = TestProject._(root);
    project.write(
      'pubspec.yaml',
      '''name: demo_app
environment:
  sdk: ">=3.11.0 <4.0.0"
''',
    );
    if (config != null) project.write('.agent_harness.yaml', config);
    project.write('.agent_harness/baseline.json', '{"version":1,"violations":[]}\n');
    return project;
  }

  File write(String relativePath, String content) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  void createDirectory(String relativePath) {
    Directory(p.join(root.path, relativePath)).createSync(recursive: true);
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
