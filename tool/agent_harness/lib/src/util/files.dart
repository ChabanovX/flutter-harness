import 'dart:io';

import 'package:path/path.dart' as p;

String toPosixPath(String value) => value.replaceAll('\\', '/');

String relativePosix(String path, {required String from}) => toPosixPath(p.relative(path, from: from));

Iterable<File> dartFilesUnder(Directory directory) sync* {
  if (!directory.existsSync()) return;

  final entities = directory.listSync(recursive: true, followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));

  for (final entity in entities) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = toPosixPath(entity.path);
    if (normalized.contains('/.dart_tool/') || normalized.contains('/build/') || normalized.contains('/.git/')) {
      continue;
    }
    yield entity;
  }
}

void writeFileIfMissing(
  File file,
  String content, {
  required bool force,
}) {
  if (file.existsSync() && !force) return;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

bool isDocumentationPath(String path) {
  final normalized = toPosixPath(path);
  return normalized.startsWith('docs/') ||
      normalized == 'README.md' ||
      normalized == 'AGENTS.md' ||
      normalized.endsWith('.md');
}
