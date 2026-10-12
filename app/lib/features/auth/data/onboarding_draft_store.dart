import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/onboarding_data.dart';

/// Keeps an unfinished onboarding form on the device (UC1.4 A1, D-25).
abstract interface class OnboardingDraftStore {
  Future<OnboardingData?> load(String uid);
  Future<void> save(String uid, OnboardingData data, int step);
  Future<int> loadStep(String uid);
  Future<void> clear(String uid);
}

class SharedPrefsOnboardingDraftStore implements OnboardingDraftStore {
  static String _key(String uid) => 'onboarding_draft_$uid';
  static String _stepKey(String uid) => 'onboarding_step_$uid';

  @override
  Future<OnboardingData?> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(uid));
    if (raw == null) return null;
    try {
      return OnboardingData.fromDraftJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear(uid); // corrupt or outdated draft: start fresh
      return null;
    }
  }

  @override
  Future<int> loadStep(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_stepKey(uid)) ?? 0;
  }

  @override
  Future<void> save(String uid, OnboardingData data, int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), jsonEncode(data.toDraftJson()));
    await prefs.setInt(_stepKey(uid), step);
  }

  @override
  Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
    await prefs.remove(_stepKey(uid));
  }
}
