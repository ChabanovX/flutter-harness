import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/harness_config.dart';
import '../util/files.dart';
import 'naming.dart';
import 'templates.dart';

final class ScaffoldResult {
  const ScaffoldResult({required this.written, required this.skipped});

  final List<String> written;
  final List<String> skipped;
}

final class FeatureScaffolder {
  const FeatureScaffolder(this.config);

  final HarnessConfig config;

  ScaffoldResult scaffold({
    required FeatureNaming naming,
    required String stateStyle,
    required bool force,
    required bool dryRun,
    required bool generateGetItModule,
    required bool generateWidgetTest,
  }) {
    if (stateStyle != 'sealed' && stateStyle != 'status') {
      throw FormatException(
        'state must be either "sealed" or "status", got: $stateStyle',
      );
    }

    final featureBase = p.posix.join(
      toPosixPath(config.project.featureRoot),
      naming.featureSnake,
    );
    final templates = FeatureTemplates(
      packageName: config.packageName,
      naming: naming,
      stateStyle: stateStyle,
      featurePackageRoot: config.project.packagePath(featureBase),
      sharedDomainPackageRoot: config.project.packagePath(config.project.sharedDomainRoot),
      failureMapperPackagePath: config.project.packagePath(
        p.posix.join(config.project.coreRoot, 'errors/failure_mapper.dart'),
      ),
    );
    final testBase = p.posix.join('test/features', naming.featureSnake);

    final files = <String, String>{
      p.posix.join(
        featureBase,
        'domain/entities/${naming.entitySnake}.dart',
      ): templates.domainEntity,
      p.posix.join(
        featureBase,
        'application/ports/${naming.featureSnake}_repository.dart',
      ): templates.repositoryPort,
      p.posix.join(
        featureBase,
        'application/queries/get_${naming.featureSnake}.dart',
      ): templates.query,
      p.posix.join(
        featureBase,
        'data/dto/${naming.entitySnake}_dto.dart',
      ): templates.dto,
      p.posix.join(
        featureBase,
        'data/mappers/${naming.entitySnake}_mapper.dart',
      ): templates.mapper,
      p.posix.join(
        featureBase,
        'data/datasources/${naming.featureSnake}_remote_data_source.dart',
      ): templates.dataSource,
      p.posix.join(
        featureBase,
        'data/repositories/${naming.featureSnake}_repository_impl.dart',
      ): templates.repositoryImplementation,
      p.posix.join(
        featureBase,
        'presentation/cubit/${naming.featureSnake}_state.dart',
      ): templates.state,
      p.posix.join(
        featureBase,
        'presentation/cubit/${naming.featureSnake}_cubit.dart',
      ): templates.cubit,
      p.posix.join(
        featureBase,
        'presentation/pages/${naming.featureSnake}_page.dart',
      ): templates.page,
      p.posix.join(
        testBase,
        'data/mappers/${naming.entitySnake}_mapper_test.dart',
      ): templates.mapperTest,
      p.posix.join(
        testBase,
        'application/queries/get_${naming.featureSnake}_test.dart',
      ): templates.queryTest,
      p.posix.join(
        testBase,
        'data/repositories/${naming.featureSnake}_repository_impl_test.dart',
      ): templates.repositoryTest,
      p.posix.join(
        testBase,
        'presentation/cubit/${naming.featureSnake}_cubit_test.dart',
      ): templates.cubitTest,
    };

    if (generateGetItModule) {
      files[p.posix.join(
            config.project.appRoot,
            'di/${naming.featureSnake}_module.dart',
          )] =
          templates.diModule;
    }
    if (generateWidgetTest) {
      files[p.posix.join(
            testBase,
            'presentation/pages/${naming.featureSnake}_page_test.dart',
          )] =
          templates.widgetTest;
    }

    final written = <String>[];
    final skipped = <String>[];
    for (final entry in files.entries) {
      final absolute = File(p.join(config.root.path, entry.key));
      if (absolute.existsSync() && !force) {
        skipped.add(entry.key);
        continue;
      }
      written.add(entry.key);
      if (!dryRun) {
        absolute.parent.createSync(recursive: true);
        absolute.writeAsStringSync(entry.value);
      }
    }

    return ScaffoldResult(
      written: List.unmodifiable(written),
      skipped: List.unmodifiable(skipped),
    );
  }
}
