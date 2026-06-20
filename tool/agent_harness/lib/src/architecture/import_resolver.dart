import 'package:path/path.dart' as p;

import '../util/files.dart';

sealed class ImportTarget {
  const ImportTarget(this.uri);

  final String uri;
}

final class DartImportTarget extends ImportTarget {
  const DartImportTarget(super.uri);
}

final class InternalImportTarget extends ImportTarget {
  const InternalImportTarget(super.uri, this.path);

  final String path;
}

final class ExternalPackageTarget extends ImportTarget {
  const ExternalPackageTarget(super.uri, this.packageName);

  final String packageName;
}

final class UnknownImportTarget extends ImportTarget {
  const UnknownImportTarget(super.uri);
}

final class ImportResolver {
  const ImportResolver({
    required this.packageName,
    required this.libRoot,
  });

  final String packageName;
  final String libRoot;

  ImportTarget resolve({
    required String sourcePath,
    required String uri,
  }) {
    if (uri.startsWith('dart:')) return DartImportTarget(uri);

    if (uri.startsWith('package:')) {
      final body = uri.substring('package:'.length);
      final slash = body.indexOf('/');
      final importedPackage = slash == -1 ? body : body.substring(0, slash);
      if (importedPackage != packageName) {
        return ExternalPackageTarget(uri, importedPackage);
      }
      final packagePath = slash == -1 ? '' : body.substring(slash + 1);
      return InternalImportTarget(
        uri,
        p.posix.normalize(p.posix.join(libRoot, packagePath)),
      );
    }

    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.hasScheme) {
      return UnknownImportTarget(uri);
    }

    final sourceDirectory = p.posix.dirname(toPosixPath(sourcePath));
    return InternalImportTarget(
      uri,
      p.posix.normalize(p.posix.join(sourceDirectory, uri)),
    );
  }
}
