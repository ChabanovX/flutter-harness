import 'dart:io';

import 'package:path/path.dart' as p;

Directory findProjectRoot({String? explicitRoot}) {
  if (explicitRoot != null && explicitRoot.trim().isNotEmpty) {
    final directory = Directory(p.normalize(p.absolute(explicitRoot)));
    _validateProjectRoot(directory);
    return directory;
  }

  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'pubspec.yaml')).existsSync()) {
      return current;
    }

    final parent = current.parent;
    if (p.equals(parent.path, current.path)) {
      throw StateError(
        'Could not find pubspec.yaml. Run the harness from a Dart/Flutter '
        'project or pass --root.',
      );
    }
    current = parent;
  }
}

void _validateProjectRoot(Directory directory) {
  if (!directory.existsSync()) {
    throw StateError('Project root does not exist: ${directory.path}');
  }
  if (!File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
    throw StateError('No pubspec.yaml found at ${directory.path}');
  }
}
