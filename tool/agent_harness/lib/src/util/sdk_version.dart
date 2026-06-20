final class SdkVersion implements Comparable<SdkVersion> {
  const SdkVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static SdkVersion? tryParse(String value) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    if (match == null) return null;
    return SdkVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(SdkVersion other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) return majorComparison;
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) return minorComparison;
    return patch.compareTo(other.patch);
  }

  bool operator <(SdkVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) {
    return other is SdkVersion && other.major == major && other.minor == minor && other.patch == patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

const recommendedFlutterVersion = SdkVersion(3, 44, 2);
const recommendedFlutterDartVersion = SdkVersion(3, 12, 2);
