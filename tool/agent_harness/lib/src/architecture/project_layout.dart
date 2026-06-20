import 'package:path/path.dart' as p;

import '../config/harness_config.dart';
import '../util/files.dart';

enum ArchitectureZone {
  app,
  core,
  sharedDomain,
  sharedOther,
  featureDomain,
  featureApplication,
  featureData,
  featurePresentation,
  unclassified,
}

final class SourceLocation {
  const SourceLocation({
    required this.path,
    required this.zone,
    this.feature,
    this.isUnderFeatureRoot = false,
  });

  final String path;
  final ArchitectureZone zone;
  final String? feature;
  final bool isUnderFeatureRoot;

  bool get isFeature => feature != null;
}

final class ProjectLayout {
  ProjectLayout(HarnessConfig config)
      : _libRoot = _normalize(config.project.libRoot),
        _featureRoot = _normalize(config.project.featureRoot),
        _appRoot = _normalize(config.project.appRoot),
        _coreRoot = _normalize(config.project.coreRoot),
        _sharedRoot = _normalize(config.project.sharedRoot);

  final String _libRoot;
  final String _featureRoot;
  final String _appRoot;
  final String _coreRoot;
  final String _sharedRoot;

  SourceLocation classify(String relativePath) {
    final path = _normalize(relativePath);

    if (_isInside(path, _featureRoot)) {
      final remainder = p.posix.relative(path, from: _featureRoot);
      final segments = p.posix.split(remainder);
      if (segments.length >= 2) {
        final feature = segments[0];
        final layer = segments[1];
        final zone = switch (layer) {
          'domain' => ArchitectureZone.featureDomain,
          'application' => ArchitectureZone.featureApplication,
          'data' => ArchitectureZone.featureData,
          'presentation' => ArchitectureZone.featurePresentation,
          _ => ArchitectureZone.unclassified,
        };
        return SourceLocation(
          path: path,
          zone: zone,
          feature: feature,
          isUnderFeatureRoot: true,
        );
      }
      return SourceLocation(
        path: path,
        zone: ArchitectureZone.unclassified,
        feature: segments.isEmpty ? null : segments.first,
        isUnderFeatureRoot: true,
      );
    }

    if (_isInside(path, _appRoot)) {
      return SourceLocation(path: path, zone: ArchitectureZone.app);
    }
    if (_isInside(path, _coreRoot)) {
      return SourceLocation(path: path, zone: ArchitectureZone.core);
    }
    if (_isInside(path, _sharedRoot)) {
      final sharedDomainRoot = p.posix.join(_sharedRoot, 'domain');
      return SourceLocation(
        path: path,
        zone: _isInside(path, sharedDomainRoot)
            ? ArchitectureZone.sharedDomain
            : ArchitectureZone.sharedOther,
      );
    }
    if (_isInside(path, _libRoot)) {
      return SourceLocation(path: path, zone: ArchitectureZone.unclassified);
    }

    return SourceLocation(path: path, zone: ArchitectureZone.unclassified);
  }

  static String _normalize(String value) =>
      p.posix.normalize(toPosixPath(value));

  static bool _isInside(String path, String root) =>
      path == root || p.posix.isWithin(root, path);
}
