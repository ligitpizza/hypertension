import 'dart:convert';

/// FR-10.3 / FR-14.4 NLP message analysis (docs/06 section H; D-09, D-42).
///
/// Rule-based: a message is flagged when it contains a high-risk phrase that is not
/// negated by a word in the few words before it ("no longer have chest pain").
/// Runs on the sending device before encryption, because the server cannot read messages.
/// Residual false positives/negatives are a documented limitation; the doctor can dismiss
/// a false flag (UC10.3 E1).
class KeywordScanner {
  KeywordScanner({required List<String> phrases, required List<String> negations})
    : _phrases = [for (final p in phrases) _normalise(p)]..sort((a, b) => b.length - a.length),
      _negations = [for (final n in negations) _normalise(n)];

  factory KeywordScanner.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return KeywordScanner(
      phrases: [for (final p in data['phrases'] as List<dynamic>) '$p'],
      negations: [for (final n in data['negations'] as List<dynamic>) '$n'],
    );
  }

  static const assetPath = 'assets/high_risk_keywords.json';

  /// How many words before a phrase are checked for a negation.
  static const negationWindow = 4;

  final List<String> _phrases;
  final List<String> _negations;

  /// "Can’t" / "cant" / "can not" all become "can't"; punctuation becomes spaces.
  static String _normalise(String text) {
    var t = text.toLowerCase().replaceAll(RegExp('[‘’`]'), "'");
    t = t.replaceAll(RegExp(r"\bcant\b"), "can't").replaceAll(RegExp(r'\bcan not\b'), "can't");
    t = t.replaceAll(RegExp(r"\bcannot\b"), "can't");
    t = t.replaceAll(RegExp(r"[^a-z0-9' ]+"), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The distinct high-risk phrases found (not negated), in list order.
  List<String> scan(String message) {
    final words = _normalise(message).split(' ');
    final text = ' ${words.join(' ')} ';
    final found = <String>[];
    for (final phrase in _phrases) {
      var from = 0;
      while (true) {
        final at = text.indexOf(' $phrase ', from);
        if (at < 0) break;
        if (!_negated(text.substring(0, at + 1))) {
          found.add(phrase);
          break;
        }
        from = at + 1;
      }
    }
    // A longer phrase already covers its shorter parts ("numbness" vs "numb").
    return [
      for (final p in found)
        if (!found.any((other) => other != p && other.contains(p))) p,
    ];
  }

  bool _negated(String before) {
    final prior = before.trim().split(' ').where((w) => w.isNotEmpty).toList();
    final window = prior.length <= negationWindow
        ? prior
        : prior.sublist(prior.length - negationWindow);
    final joined = ' ${window.join(' ')} ';
    return _negations.any((n) => joined.contains(' $n '));
  }

  bool isHighRisk(String message) => scan(message).isNotEmpty;
}
