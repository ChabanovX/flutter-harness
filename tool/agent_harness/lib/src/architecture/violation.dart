import 'dart:convert';
import 'dart:io';

final class ArchitectureViolation implements Comparable<ArchitectureViolation> {
  const ArchitectureViolation({
    required this.rule,
    required this.path,
    required this.line,
    required this.message,
    required this.anchor,
    this.target,
  });

  final String rule;
  final String path;
  final int line;
  final String message;
  final String anchor;
  final String? target;

  String get fingerprint => '$rule|$path|${target ?? ''}|$anchor';

  Map<String, Object?> toJson() => {
        'fingerprint': fingerprint,
        'rule': rule,
        'path': path,
        'line': line,
        if (target != null) 'target': target,
        'message': message,
      };

  @override
  int compareTo(ArchitectureViolation other) {
    final pathOrder = path.compareTo(other.path);
    if (pathOrder != 0) return pathOrder;
    final lineOrder = line.compareTo(other.line);
    if (lineOrder != 0) return lineOrder;
    return rule.compareTo(other.rule);
  }
}

final class ViolationBaseline {
  const ViolationBaseline(this.fingerprints);

  final Set<String> fingerprints;

  static ViolationBaseline load(File file) {
    if (!file.existsSync()) return const ViolationBaseline(<String>{});

    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Architecture baseline must be a JSON map.');
    }
    final entries = decoded['violations'];
    if (entries is! List) return const ViolationBaseline(<String>{});

    final fingerprints = <String>{};
    for (final entry in entries) {
      if (entry is String) {
        fingerprints.add(entry);
      } else if (entry is Map) {
        final fingerprint = entry['fingerprint'];
        if (fingerprint != null) fingerprints.add(fingerprint.toString());
      }
    }
    return ViolationBaseline(Set.unmodifiable(fingerprints));
  }

  static void write(File file, Iterable<ArchitectureViolation> violations) {
    final sorted = violations.toList()..sort();
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final encoded = encoder.convert({
      'version': 1,
      'violations': sorted.map((item) => item.toJson()).toList(),
    });
    file.writeAsStringSync('$encoded\n');
  }
}

final class ArchitectureReport {
  const ArchitectureReport({
    required this.violations,
    required this.newViolations,
    required this.acceptedViolations,
    required this.staleBaselineFingerprints,
  });

  final List<ArchitectureViolation> violations;
  final List<ArchitectureViolation> newViolations;
  final List<ArchitectureViolation> acceptedViolations;
  final List<String> staleBaselineFingerprints;

  Map<String, Object?> toJson() => {
        'summary': {
          'total': violations.length,
          'new': newViolations.length,
          'accepted': acceptedViolations.length,
          'stale_baseline': staleBaselineFingerprints.length,
        },
        'new_violations': newViolations.map((item) => item.toJson()).toList(),
        'accepted_violations':
            acceptedViolations.map((item) => item.toJson()).toList(),
        'stale_baseline_fingerprints': staleBaselineFingerprints,
      };
}
