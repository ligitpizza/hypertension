import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/messaging/domain/keyword_scanner.dart';

// FR-10.3 / FR-14.4 keyword scan with simple negation (docs/06 section H, D-09).
void main() {
  final scanner = KeywordScanner.fromJson(
    File('assets/high_risk_keywords.json').readAsStringSync(),
  );

  group('flags high-risk messages', () {
    for (final (text, phrase) in [
      ('I woke up with chest pain', 'chest pain'),
      ("I can't breathe properly", "can't breathe"),
      ('I cant breathe', "can't breathe"),
      ('I cannot breathe', "can't breathe"),
      ('My left arm has numbness', 'numbness'),
      ('Had a SEVERE HEADACHE since morning!!', 'severe headache'),
      ('I fainted in the kitchen', 'fainted'),
      ('Pandangan kabur dan sakit dada', 'sakit dada'),
    ]) {
      test(text, () => expect(scanner.scan(text), contains(phrase)));
    }
  });

  group('negation cancels a phrase', () {
    for (final text in [
      'I have no chest pain today',
      'No longer have chest pain, thanks doctor',
      "I don't have shortness of breath",
      'Never fainted before',
      'Not dizzy and no blurred vision',
    ]) {
      test(text, () => expect(scanner.isHighRisk(text), isFalse));
    }
  });

  test('a negation far before the phrase does not cancel it', () {
    expect(scanner.isHighRisk('No problem with meds, but now I have chest pain'), isTrue);
  });

  test('a later un-negated mention still counts', () {
    expect(scanner.scan('No chest pain yesterday. Today the chest pain is back'), ['chest pain']);
  });

  test('ordinary messages are not flagged', () {
    for (final text in [
      'My BP was 128/82 this morning',
      'Can I take my medicine after breakfast?',
      'Thank you doctor, see you next week',
      'The pain in my knee is better',
    ]) {
      expect(scanner.isHighRisk(text), isFalse, reason: text);
    }
  });

  test('a longer phrase is reported instead of its shorter part', () {
    expect(scanner.scan('numbness in my hand'), ['numbness']);
  });
}
