final class FeatureNaming {
  FeatureNaming({required String feature, String? entity})
    : featureSnake = _validateSnakeCase(feature, label: 'feature'),
      entitySnake = _validateSnakeCase(
        entity ?? _singularize(feature),
        label: 'entity',
      );

  final String featureSnake;
  final String entitySnake;

  String get featurePascal => _pascal(featureSnake);
  String get featureCamel => _camel(featureSnake);
  String get entityPascal => _pascal(entitySnake);
  String get entityCamel => _camel(entitySnake);

  static String _validateSnakeCase(String value, {required String label}) {
    final normalized = value.trim();
    if (!RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(normalized)) {
      throw FormatException(
        '$label must be lower_snake_case and start with a letter: $value',
      );
    }
    return normalized;
  }

  static String _singularize(String value) {
    if (value.endsWith('ies') && value.length > 3) {
      return '${value.substring(0, value.length - 3)}y';
    }
    if ((value.endsWith('sses') ||
            value.endsWith('xes') ||
            value.endsWith('zes') ||
            value.endsWith('ches') ||
            value.endsWith('shes')) &&
        value.length > 3) {
      return value.substring(0, value.length - 2);
    }
    if (value.endsWith('s') && !value.endsWith('ss') && value.length > 1) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _pascal(String value) => value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();

  static String _camel(String value) {
    final pascal = _pascal(value);
    return '${pascal[0].toLowerCase()}${pascal.substring(1)}';
  }
}
