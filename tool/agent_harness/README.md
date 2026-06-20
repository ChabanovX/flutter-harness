# agent_harness

Isolated Dart package used by the parent Flutter project's `tool/harness.dart` launcher. Keep its dependencies out of the application's `pubspec.yaml`; the launcher runs this package in its own package context.

Direct self-checks:

```bash
dart pub get
dart analyze
dart test
```
