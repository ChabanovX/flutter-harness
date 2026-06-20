import 'package:agent_harness/src/scaffold/naming.dart';
import 'package:test/test.dart';

void main() {
  group('FeatureNaming', () {
    test('derives identifier forms and a common singular entity', () {
      final naming = FeatureNaming(feature: 'push_notifications');

      expect(naming.featurePascal, 'PushNotifications');
      expect(naming.featureCamel, 'pushNotifications');
      expect(naming.entitySnake, 'push_notification');
      expect(naming.entityPascal, 'PushNotification');
    });

    test('handles common es plurals without truncating course', () {
      expect(FeatureNaming(feature: 'courses').entitySnake, 'course');
      expect(FeatureNaming(feature: 'classes').entitySnake, 'class');
      expect(FeatureNaming(feature: 'categories').entitySnake, 'category');
    });

    test('accepts an explicit entity for irregular nouns', () {
      final naming = FeatureNaming(feature: 'people', entity: 'person');

      expect(naming.entityPascal, 'Person');
    });

    test('rejects names outside lower_snake_case', () {
      for (final invalid in [
        'PushNotifications',
        'bad__name',
        'bad_name_',
        '_bad',
      ]) {
        expect(
          () => FeatureNaming(feature: invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
    });
  });
}
