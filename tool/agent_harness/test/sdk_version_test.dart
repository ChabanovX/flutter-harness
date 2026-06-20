import 'package:agent_harness/src/util/sdk_version.dart';
import 'package:test/test.dart';

void main() {
  test('parses semantic SDK versions from plain and annotated strings', () {
    expect(SdkVersion.tryParse('3.44.2'), const SdkVersion(3, 44, 2));
    expect(SdkVersion.tryParse('3.12.2 (stable)'), const SdkVersion(3, 12, 2));
    expect(SdkVersion.tryParse('unknown'), isNull);
  });

  test('compares SDK versions by major, minor, and patch', () {
    expect(const SdkVersion(3, 41, 4) < recommendedFlutterVersion, isTrue);
    expect(const SdkVersion(3, 44, 2) < recommendedFlutterVersion, isFalse);
    expect(const SdkVersion(3, 44, 3) < recommendedFlutterVersion, isFalse);
  });
}
