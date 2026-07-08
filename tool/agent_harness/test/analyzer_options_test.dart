import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('tool package uses the shared harness analyzer preset', () {
    final options = File('analysis_options.yaml').readAsStringSync();

    expect(options, contains('../../analysis_options.harness.snippet.yaml'));
  });

  test('shared analyzer preset matches the fl_init_analyzer defaults', () {
    final options =
        loadYaml(
              File('../../analysis_options.harness.snippet.yaml').readAsStringSync(),
            )
            as YamlMap;
    final include = options['include'] as YamlList;
    final formatter = options['formatter'] as YamlMap;
    final analyzer = options['analyzer'] as YamlMap;
    final linter = options['linter'] as YamlMap;
    final errors = analyzer['errors'] as YamlMap;
    final excluded = (analyzer['exclude'] as YamlList).cast<String>();
    final rules = linter['rules'] as YamlMap;

    expect(include, contains('package:bloc_lint/recommended.yaml'));
    expect(include, contains('package:very_good_analysis/analysis_options.yaml'));
    expect(formatter['page_width'], 120);
    expect(formatter['trailing_commas'], 'preserve');
    expect(errors['invalid_annotation_target'], 'ignore');
    expect(excluded, contains('tool/agent_harness/**'));
    expect(excluded, contains('**/*.freezed.dart'));
    expect(rules['public_member_api_docs'], isFalse);
    expect(rules['lines_longer_than_80_chars'], isFalse);
  });
}
