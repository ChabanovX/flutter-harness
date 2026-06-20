import 'package:agent_harness/src/scaffold/naming.dart';
import 'package:agent_harness/src/scaffold/templates.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';

void main() {
  for (final stateStyle in ['sealed', 'status']) {
    test('all $stateStyle feature templates parse', () {
      final templates = FeatureTemplates(
        packageName: 'demo_app',
        naming: FeatureNaming(feature: 'notifications', entity: 'notification'),
        stateStyle: stateStyle,
        featurePackageRoot: 'features/notifications',
        sharedDomainPackageRoot: 'shared/domain',
        failureMapperPackagePath: 'core/errors/failure_mapper.dart',
      );
      final sources = <String, String>{
        'domain entity': templates.domainEntity,
        'repository port': templates.repositoryPort,
        'query': templates.query,
        'DTO': templates.dto,
        'mapper': templates.mapper,
        'data source': templates.dataSource,
        'repository implementation': templates.repositoryImplementation,
        'state': templates.state,
        'cubit': templates.cubit,
        'page': templates.page,
        'DI module': templates.diModule,
        'mapper test': templates.mapperTest,
        'query test': templates.queryTest,
        'repository test': templates.repositoryTest,
        'cubit test': templates.cubitTest,
        'widget test': templates.widgetTest,
      };

      for (final entry in sources.entries) {
        final result = parseString(
          content: entry.value,
          path: '${entry.key.replaceAll(' ', '_')}.dart',
          featureSet: FeatureSet.latestLanguageVersion(),
          throwIfDiagnostics: false,
        );
        expect(
          result.errors,
          isEmpty,
          reason: '${entry.key} failed to parse:\n${result.errors.join('\n')}',
        );
      }
    });

    test('$stateStyle Cubit template documents its concurrency policy', () {
      final templates = FeatureTemplates(
        packageName: 'demo_app',
        naming: FeatureNaming(feature: 'notifications', entity: 'notification'),
        stateStyle: stateStyle,
        featurePackageRoot: 'features/notifications',
        sharedDomainPackageRoot: 'shared/domain',
        failureMapperPackagePath: 'core/errors/failure_mapper.dart',
      );

      expect(
        templates.cubit,
        contains('Concurrency policy: ignore overlapping load() calls'),
      );
    });
  }
}
