# agent_harness

Isolated Dart package used by the parent Flutter project's `tool/harness.dart` launcher. Keep its dependencies out of the application's `pubspec.yaml`; the launcher runs this package in its own package context.

Direct self-checks:

```bash
dart pub get
dart analyze
dart test
```

Application-facing commands exposed by this package include:

```bash
dart run tool/harness.dart quality
dart run tool/harness.dart architecture --json
dart run tool/harness.dart generate
dart run tool/harness.dart golden
dart run tool/harness.dart verify --changed
```

Navigation placement and authority violations are architecture violations, so they participate in exceptions, the shrink-only baseline, JSON reports, and `verify`.
