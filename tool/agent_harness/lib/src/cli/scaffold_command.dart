import 'package:args/command_runner.dart';

import '../scaffold/feature_scaffolder.dart';
import '../scaffold/naming.dart';
import 'command_context.dart';

final class ScaffoldCommand extends Command<int> {
  ScaffoldCommand() {
    addSubcommand(ScaffoldFeatureCommand());
  }

  @override
  String get description => 'Generate deterministic architecture slices.';

  @override
  String get name => 'scaffold';
}

final class ScaffoldFeatureCommand extends Command<int> {
  ScaffoldFeatureCommand() {
    argParser
      ..addOption(
        'entity',
        help: 'Singular lower_snake_case domain entity name.',
      )
      ..addOption(
        'state',
        allowed: const ['sealed', 'status'],
        help: 'Cubit state style. Defaults to .agent_harness.yaml.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite generated feature files.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'List files without writing them.',
      )
      ..addFlag(
        'get-it-module',
        defaultsTo: null,
        help: 'Generate an app DI registration module.',
      )
      ..addFlag(
        'widget-test',
        defaultsTo: null,
        help: 'Generate a widget test.',
      );
  }

  @override
  String get description => 'Generate one feature-first vertical slice.';

  @override
  String get name => 'feature';

  @override
  String get invocation => '${super.invocation} <feature_name>';

  @override
  Future<int> run() async {
    final context = CommandContext.from(this);
    final rest = argResults?.rest ?? const [];
    if (rest.length != 1) {
      throw UsageException(
        'Provide exactly one lower_snake_case feature name.',
        usage,
      );
    }

    final naming = FeatureNaming(
      feature: rest.single,
      entity: argResults?['entity'] as String?,
    );
    final stateStyle = argResults?['state'] as String? ??
        context.config.scaffolding.defaultStateStyle;
    final force = argResults?['force'] as bool? ?? false;
    final dryRun = argResults?['dry-run'] as bool? ?? false;
    final getItOverride = argResults?['get-it-module'] as bool?;
    final widgetTestOverride = argResults?['widget-test'] as bool?;

    final result = FeatureScaffolder(context.config).scaffold(
      naming: naming,
      stateStyle: stateStyle,
      force: force,
      dryRun: dryRun,
      generateGetItModule: getItOverride ??
          context.config.scaffolding.generateGetItModule,
      generateWidgetTest: widgetTestOverride ??
          context.config.scaffolding.generateWidgetTest,
    );

    context.console.heading(
      '${dryRun ? 'Scaffold preview' : 'Scaffolded'} '
      '${naming.featurePascal}',
    );
    for (final path in result.written) {
      context.console.success('${dryRun ? 'Would write' : 'Wrote'} $path');
    }
    for (final path in result.skipped) {
      context.console.warning('Preserved existing $path');
    }

    if (!dryRun && result.written.isNotEmpty) {
      final formatCode = await context.executor.run(
        'dart',
        ['format', ...result.written],
      );
      if (formatCode != 0) {
        context.console.error('Generated files could not be formatted.');
        return formatCode;
      }
    }

    context.console.info('Integration steps:');
    context.console.info(
      '  1. Implement and register a concrete '
      '${naming.featurePascal}RemoteDataSource.',
    );
    context.console.info(
      '  2. Call register${naming.featurePascal}Module() from configureDependencies().',
    );
    context.console.info(
      '  3. Add a router/provider factory that creates '
      '${naming.featurePascal}Cubit()..load().',
    );
    context.console.info(
      '  4. Run dart run tool/harness.dart verify --changed.',
    );
    return 0;
  }
}
