import 'naming.dart';

final class FeatureTemplates {
  const FeatureTemplates({
    required this.packageName,
    required this.naming,
    required this.stateStyle,
    required this.featurePackageRoot,
    required this.sharedDomainPackageRoot,
    required this.failureMapperPackagePath,
    required this.designTokensPackagePath,
    required this.localizationsPackagePath,
    required this.localizationsClass,
  });

  final String packageName;
  final FeatureNaming naming;
  final String stateStyle;
  final String featurePackageRoot;
  final String sharedDomainPackageRoot;
  final String failureMapperPackagePath;
  final String designTokensPackagePath;
  final String localizationsPackagePath;
  final String localizationsClass;

  String get domainEntity =>
      '''final class ${naming.entityPascal} {
  const ${naming.entityPascal}({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ${naming.entityPascal} &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title;

  @override
  int get hashCode => Object.hash(id, title);
}
''';

  String get repositoryPort =>
      '''import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

abstract interface class ${naming.featurePascal}Repository {
  Future<AppResult<List<${naming.entityPascal}>>> get${naming.featurePascal}();
}
''';

  String get query =>
      '''import 'package:$packageName/$featurePackageRoot/application/ports/${naming.featureSnake}_repository.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

final class Get${naming.featurePascal} {
  const Get${naming.featurePascal}(this._repository);

  final ${naming.featurePascal}Repository _repository;

  Future<AppResult<List<${naming.entityPascal}>>> call() =>
      _repository.get${naming.featurePascal}();
}
''';

  String get dto =>
      '''final class ${naming.entityPascal}Dto {
  const ${naming.entityPascal}Dto({
    required this.id,
    required this.title,
  });

  factory ${naming.entityPascal}Dto.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) {
      throw const FormatException(
        'Expected non-null string fields: id and title.',
      );
    }
    return ${naming.entityPascal}Dto(id: id, title: title);
  }

  final String id;
  final String title;
}
''';

  String get mapper =>
      '''import 'package:$packageName/$featurePackageRoot/data/dto/${naming.entitySnake}_dto.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';

abstract final class ${naming.entityPascal}Mapper {
  static ${naming.entityPascal} fromDto(${naming.entityPascal}Dto dto) {
    return ${naming.entityPascal}(id: dto.id, title: dto.title);
  }
}
''';

  String get dataSource =>
      '''import 'package:$packageName/$featurePackageRoot/data/dto/${naming.entitySnake}_dto.dart';

abstract interface class ${naming.featurePascal}RemoteDataSource {
  Future<List<${naming.entityPascal}Dto>> fetch${naming.featurePascal}();
}
''';

  String get repositoryImplementation =>
      '''import 'package:$packageName/$failureMapperPackagePath';
import 'package:$packageName/$featurePackageRoot/application/ports/${naming.featureSnake}_repository.dart';
import 'package:$packageName/$featurePackageRoot/data/datasources/${naming.featureSnake}_remote_data_source.dart';
import 'package:$packageName/$featurePackageRoot/data/mappers/${naming.entitySnake}_mapper.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

final class ${naming.featurePascal}RepositoryImpl
    implements ${naming.featurePascal}Repository {
  const ${naming.featurePascal}RepositoryImpl({
    required ${naming.featurePascal}RemoteDataSource remoteDataSource,
    required FailureMapper failureMapper,
  })  : _remoteDataSource = remoteDataSource,
        _failureMapper = failureMapper;

  final ${naming.featurePascal}RemoteDataSource _remoteDataSource;
  final FailureMapper _failureMapper;

  @override
  Future<AppResult<List<${naming.entityPascal}>>> get${naming.featurePascal}() async {
    try {
      final dtoItems = await _remoteDataSource.fetch${naming.featurePascal}();
      final items = dtoItems
          .map(${naming.entityPascal}Mapper.fromDto)
          .toList(growable: false);
      return AppSuccess(List.unmodifiable(items));
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(_failureMapper.map(error, stackTrace));
    }
  }
}
''';

  String get state => stateStyle == 'status' ? _statusState : _sealedState;

  String get cubit => stateStyle == 'status' ? _statusCubit : _sealedCubit;

  String get page => stateStyle == 'status' ? _statusPage : _sealedPage;

  String get diModule =>
      '''import 'package:get_it/get_it.dart';
import 'package:$packageName/$failureMapperPackagePath';
import 'package:$packageName/$featurePackageRoot/application/ports/${naming.featureSnake}_repository.dart';
import 'package:$packageName/$featurePackageRoot/application/queries/get_${naming.featureSnake}.dart';
import 'package:$packageName/$featurePackageRoot/data/datasources/${naming.featureSnake}_remote_data_source.dart';
import 'package:$packageName/$featurePackageRoot/data/repositories/${naming.featureSnake}_repository_impl.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_cubit.dart';

void register${naming.featurePascal}Module(GetIt getIt) {
  if (!getIt.isRegistered<${naming.featurePascal}RemoteDataSource>()) {
    throw StateError(
      'Register a concrete ${naming.featurePascal}RemoteDataSource before '
      'register${naming.featurePascal}Module().',
    );
  }
  if (!getIt.isRegistered<FailureMapper>()) {
    throw StateError(
      'Register FailureMapper in the core DI module first.',
    );
  }

  if (!getIt.isRegistered<${naming.featurePascal}Repository>()) {
    getIt.registerLazySingleton<${naming.featurePascal}Repository>(
      () => ${naming.featurePascal}RepositoryImpl(
        remoteDataSource: getIt(),
        failureMapper: getIt(),
      ),
    );
  }
  if (!getIt.isRegistered<Get${naming.featurePascal}>()) {
    getIt.registerLazySingleton<Get${naming.featurePascal}>(
      () => Get${naming.featurePascal}(getIt()),
    );
  }
  if (!getIt.isRegistered<${naming.featurePascal}Cubit>()) {
    getIt.registerFactory<${naming.featurePascal}Cubit>(
      () => ${naming.featurePascal}Cubit(
        get${naming.featurePascal}: getIt(),
      ),
    );
  }
}
''';

  String get mapperTest =>
      '''import 'package:flutter_test/flutter_test.dart';
import 'package:$packageName/$featurePackageRoot/data/dto/${naming.entitySnake}_dto.dart';
import 'package:$packageName/$featurePackageRoot/data/mappers/${naming.entitySnake}_mapper.dart';

void main() {
  test('parses and maps ${naming.entityPascal}Dto into the domain entity', () {
    final dto = ${naming.entityPascal}Dto.fromJson(const {
      'id': 'id-1',
      'title': 'Example',
    });

    final entity = ${naming.entityPascal}Mapper.fromDto(dto);

    expect(entity.id, 'id-1');
    expect(entity.title, 'Example');
  });
}
''';

  String get queryTest =>
      '''import 'package:flutter_test/flutter_test.dart';
import 'package:$packageName/$featurePackageRoot/application/ports/${naming.featureSnake}_repository.dart';
import 'package:$packageName/$featurePackageRoot/application/queries/get_${naming.featureSnake}.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

void main() {
  test('delegates to the repository exactly once', () async {
    final repository = _Fake${naming.featurePascal}Repository();
    final query = Get${naming.featurePascal}(repository);

    final result = await query();

    expect(repository.calls, 1);
    expect(result, isA<AppSuccess<List<${naming.entityPascal}>>>());
  });
}

final class _Fake${naming.featurePascal}Repository
    implements ${naming.featurePascal}Repository {
  int calls = 0;

  @override
  Future<AppResult<List<${naming.entityPascal}>>> get${naming.featurePascal}() async {
    calls += 1;
    return const AppSuccess([
      ${naming.entityPascal}(id: 'id-1', title: 'Example'),
    ]);
  }
}
''';

  String get repositoryTest =>
      '''import 'package:flutter_test/flutter_test.dart';
import 'package:$packageName/$failureMapperPackagePath';
import 'package:$packageName/$featurePackageRoot/data/datasources/${naming.featureSnake}_remote_data_source.dart';
import 'package:$packageName/$featurePackageRoot/data/dto/${naming.entitySnake}_dto.dart';
import 'package:$packageName/$featurePackageRoot/data/repositories/${naming.featureSnake}_repository_impl.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_failure.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

void main() {
  test('maps DTOs through the real repository boundary', () async {
    final repository = ${naming.featurePascal}RepositoryImpl(
      remoteDataSource: _FakeDataSource.success(),
      failureMapper: const _NetworkFailureMapper(),
    );

    final result = await repository.get${naming.featurePascal}();

    expect(result, isA<AppSuccess<List<${naming.entityPascal}>>>());
    final items = (result as AppSuccess<List<${naming.entityPascal}>>).value;
    expect(items.single.title, 'Example');
  });

  test('normalizes datasource errors before they leave data', () async {
    final repository = ${naming.featurePascal}RepositoryImpl(
      remoteDataSource: _FakeDataSource.failure(Exception('offline')),
      failureMapper: const _NetworkFailureMapper(),
    );

    final result = await repository.get${naming.featurePascal}();

    expect(result, isA<AppError<List<${naming.entityPascal}>>>());
    final failure = (result as AppError<List<${naming.entityPascal}>>).failure;
    expect(failure, isA<NetworkFailure>());
  });
}

final class _FakeDataSource implements ${naming.featurePascal}RemoteDataSource {
  _FakeDataSource.success() : error = null;

  _FakeDataSource.failure(this.error);

  final Object? error;

  @override
  Future<List<${naming.entityPascal}Dto>> fetch${naming.featurePascal}() async {
    final error = this.error;
    if (error != null) throw error;
    return const [
      ${naming.entityPascal}Dto(id: 'id-1', title: 'Example'),
    ];
  }
}

final class _NetworkFailureMapper implements FailureMapper {
  const _NetworkFailureMapper();

  @override
  AppFailure map(Object error, StackTrace stackTrace) {
    return NetworkFailure(cause: error, stackTrace: stackTrace);
  }
}
''';

  String get cubitTest => stateStyle == 'status' ? _statusCubitTest : _sealedCubitTest;

  String get widgetTest => stateStyle == 'status' ? _statusWidgetTest : _sealedWidgetTest;

  String get _sealedState =>
      '''import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_failure.dart';

sealed class ${naming.featurePascal}State {
  const ${naming.featurePascal}State();
}

final class ${naming.featurePascal}Initial extends ${naming.featurePascal}State {
  const ${naming.featurePascal}Initial();
}

final class ${naming.featurePascal}Loading extends ${naming.featurePascal}State {
  const ${naming.featurePascal}Loading();
}

final class ${naming.featurePascal}Empty extends ${naming.featurePascal}State {
  const ${naming.featurePascal}Empty();
}

final class ${naming.featurePascal}Loaded extends ${naming.featurePascal}State {
  const ${naming.featurePascal}Loaded(this.items);

  final List<${naming.entityPascal}> items;
}

final class ${naming.featurePascal}Failure extends ${naming.featurePascal}State {
  const ${naming.featurePascal}Failure(this.failure);

  final AppFailure failure;
}
''';

  String get _sealedCubit =>
      '''import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:$packageName/$featurePackageRoot/application/queries/get_${naming.featureSnake}.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_state.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

final class ${naming.featurePascal}Cubit extends Cubit<${naming.featurePascal}State> {
  ${naming.featurePascal}Cubit({
    required Get${naming.featurePascal} get${naming.featurePascal},
  })  : _get${naming.featurePascal} = get${naming.featurePascal},
        super(const ${naming.featurePascal}Initial());

  final Get${naming.featurePascal} _get${naming.featurePascal};
  bool _loading = false;

  Future<void> load() async {
    // Concurrency policy: ignore overlapping load() calls while the current
    // repository request is in flight.
    if (_loading) return;
    _loading = true;
    emit(const ${naming.featurePascal}Loading());

    try {
      final result = await _get${naming.featurePascal}();
      if (isClosed) return;

      switch (result) {
        case AppSuccess(value: final items):
          emit(
            items.isEmpty
                ? const ${naming.featurePascal}Empty()
                : ${naming.featurePascal}Loaded(items),
          );
        case AppError(failure: final failure):
          emit(${naming.featurePascal}Failure(failure));
      }
    } finally {
      _loading = false;
    }
  }
}
''';

  String get _sealedPage =>
      '''import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:$packageName/$designTokensPackagePath';
import 'package:$packageName/$localizationsPackagePath';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_cubit.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_state.dart';

final class ${naming.featurePascal}Page extends StatelessWidget {
  const ${naming.featurePascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = $localizationsClass.of(context);
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? AppSpacing.regular;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.featurePageTitle('${naming.featurePascal}'))),
      body: Padding(
        padding: spacing.page,
        child: BlocBuilder<${naming.featurePascal}Cubit, ${naming.featurePascal}State>(
          builder: (context, state) => switch (state) {
            ${naming.featurePascal}Initial() ||
            ${naming.featurePascal}Loading() =>
              const Center(child: CircularProgressIndicator()),
            ${naming.featurePascal}Empty() => Center(
                child: Text(l10n.emptyStateMessage),
              ),
            ${naming.featurePascal}Loaded(items: final items) => ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) => ListTile(
                  key: ValueKey(items[index].id),
                  title: Text(items[index].title),
                ),
              ),
            ${naming.featurePascal}Failure() => Center(
                child: FilledButton(
                  onPressed: context.read<${naming.featurePascal}Cubit>().load,
                  child: Text(l10n.retryAction),
                ),
              ),
          },
        ),
      ),
    );
  }
}
''';

  String get _statusState =>
      '''import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_failure.dart';

enum ${naming.featurePascal}Status {
  initial,
  loading,
  empty,
  success,
  failure,
}

final class ${naming.featurePascal}State {
  const ${naming.featurePascal}State({
    this.status = ${naming.featurePascal}Status.initial,
    this.items = const [],
    this.failure,
  });

  final ${naming.featurePascal}Status status;
  final List<${naming.entityPascal}> items;
  final AppFailure? failure;

  ${naming.featurePascal}State copyWith({
    ${naming.featurePascal}Status? status,
    List<${naming.entityPascal}>? items,
    AppFailure? Function()? failure,
  }) {
    return ${naming.featurePascal}State(
      status: status ?? this.status,
      items: items ?? this.items,
      failure: failure == null ? this.failure : failure(),
    );
  }
}
''';

  String get _statusCubit =>
      '''import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:$packageName/$featurePackageRoot/application/queries/get_${naming.featureSnake}.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_state.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

final class ${naming.featurePascal}Cubit extends Cubit<${naming.featurePascal}State> {
  ${naming.featurePascal}Cubit({
    required Get${naming.featurePascal} get${naming.featurePascal},
  })  : _get${naming.featurePascal} = get${naming.featurePascal},
        super(const ${naming.featurePascal}State());

  final Get${naming.featurePascal} _get${naming.featurePascal};
  bool _loading = false;

  Future<void> load() async {
    // Concurrency policy: ignore overlapping load() calls while the current
    // repository request is in flight.
    if (_loading) return;
    _loading = true;
    emit(
      state.copyWith(
        status: ${naming.featurePascal}Status.loading,
        failure: () => null,
      ),
    );

    try {
      final result = await _get${naming.featurePascal}();
      if (isClosed) return;

      switch (result) {
        case AppSuccess(value: final items):
          emit(
            state.copyWith(
              status: items.isEmpty
                  ? ${naming.featurePascal}Status.empty
                  : ${naming.featurePascal}Status.success,
              items: items,
              failure: () => null,
            ),
          );
        case AppError(failure: final failure):
          emit(
            state.copyWith(
              status: ${naming.featurePascal}Status.failure,
              failure: () => failure,
            ),
          );
      }
    } finally {
      _loading = false;
    }
  }
}
''';

  String get _statusPage =>
      '''import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:$packageName/$designTokensPackagePath';
import 'package:$packageName/$localizationsPackagePath';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_cubit.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_state.dart';

final class ${naming.featurePascal}Page extends StatelessWidget {
  const ${naming.featurePascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = $localizationsClass.of(context);
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? AppSpacing.regular;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.featurePageTitle('${naming.featurePascal}'))),
      body: Padding(
        padding: spacing.page,
        child: BlocBuilder<${naming.featurePascal}Cubit, ${naming.featurePascal}State>(
          builder: (context, state) => switch (state.status) {
            ${naming.featurePascal}Status.initial ||
            ${naming.featurePascal}Status.loading =>
              const Center(child: CircularProgressIndicator()),
            ${naming.featurePascal}Status.empty => Center(
                child: Text(l10n.emptyStateMessage),
              ),
            ${naming.featurePascal}Status.success => ListView.builder(
                itemCount: state.items.length,
                itemBuilder: (context, index) => ListTile(
                  key: ValueKey(state.items[index].id),
                  title: Text(state.items[index].title),
                ),
              ),
            ${naming.featurePascal}Status.failure => Center(
                child: FilledButton(
                  onPressed: context.read<${naming.featurePascal}Cubit>().load,
                  child: Text(l10n.retryAction),
                ),
              ),
          },
        ),
      ),
    );
  }
}
''';

  String get _sealedCubitTest =>
      '''import 'package:flutter_test/flutter_test.dart';
import 'package:$packageName/$featurePackageRoot/application/ports/${naming.featureSnake}_repository.dart';
import 'package:$packageName/$featurePackageRoot/application/queries/get_${naming.featureSnake}.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_cubit.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_state.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

void main() {
  test('emits loading then loaded', () async {
    final cubit = ${naming.featurePascal}Cubit(
      get${naming.featurePascal}: Get${naming.featurePascal}(
        const _SuccessRepository(),
      ),
    );
    final states = <${naming.featurePascal}State>[];
    final subscription = cubit.stream.listen(states.add);

    await cubit.load();

    expect(states, [
      isA<${naming.featurePascal}Loading>(),
      isA<${naming.featurePascal}Loaded>(),
    ]);
    await subscription.cancel();
    await cubit.close();
  });
}

final class _SuccessRepository implements ${naming.featurePascal}Repository {
  const _SuccessRepository();

  @override
  Future<AppResult<List<${naming.entityPascal}>>> get${naming.featurePascal}() async {
    return const AppSuccess([
      ${naming.entityPascal}(id: 'id-1', title: 'Example'),
    ]);
  }
}
''';

  String get _statusCubitTest =>
      '''import 'package:flutter_test/flutter_test.dart';
import 'package:$packageName/$featurePackageRoot/application/ports/${naming.featureSnake}_repository.dart';
import 'package:$packageName/$featurePackageRoot/application/queries/get_${naming.featureSnake}.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_cubit.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_state.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

void main() {
  test('emits loading then success', () async {
    final cubit = ${naming.featurePascal}Cubit(
      get${naming.featurePascal}: Get${naming.featurePascal}(
        const _SuccessRepository(),
      ),
    );
    final states = <${naming.featurePascal}State>[];
    final subscription = cubit.stream.listen(states.add);

    await cubit.load();

    expect(states.map((state) => state.status), [
      ${naming.featurePascal}Status.loading,
      ${naming.featurePascal}Status.success,
    ]);
    await subscription.cancel();
    await cubit.close();
  });
}

final class _SuccessRepository implements ${naming.featurePascal}Repository {
  const _SuccessRepository();

  @override
  Future<AppResult<List<${naming.entityPascal}>>> get${naming.featurePascal}() async {
    return const AppSuccess([
      ${naming.entityPascal}(id: 'id-1', title: 'Example'),
    ]);
  }
}
''';

  String get _sealedWidgetTest =>
      '''import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$packageName/$localizationsPackagePath';
import 'package:$packageName/$featurePackageRoot/application/ports/${naming.featureSnake}_repository.dart';
import 'package:$packageName/$featurePackageRoot/application/queries/get_${naming.featureSnake}.dart';
import 'package:$packageName/$featurePackageRoot/domain/entities/${naming.entitySnake}.dart';
import 'package:$packageName/$featurePackageRoot/presentation/cubit/${naming.featureSnake}_cubit.dart';
import 'package:$packageName/$featurePackageRoot/presentation/pages/${naming.featureSnake}_page.dart';
import 'package:$packageName/$sharedDomainPackageRoot/app_result.dart';

void main() {
  testWidgets('renders loaded items', (tester) async {
    final cubit = ${naming.featurePascal}Cubit(
      get${naming.featurePascal}: Get${naming.featurePascal}(
        const _SuccessRepository(),
      ),
    );
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: $localizationsClass.localizationsDelegates,
        supportedLocales: $localizationsClass.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: const ${naming.featurePascal}Page(),
        ),
      ),
    );

    expect(find.text('Example'), findsOneWidget);
    await cubit.close();
  });
}

final class _SuccessRepository implements ${naming.featurePascal}Repository {
  const _SuccessRepository();

  @override
  Future<AppResult<List<${naming.entityPascal}>>> get${naming.featurePascal}() async {
    return const AppSuccess([
      ${naming.entityPascal}(id: 'id-1', title: 'Example'),
    ]);
  }
}
''';

  String get _statusWidgetTest => _sealedWidgetTest;
}
