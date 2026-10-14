import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/onboarding_data.dart';

/// UC12.4 E1: a recurring prescription will stop if the account is deleted.
class RecurringPrescriptionWarning implements Exception {
  const RecurringPrescriptionWarning(this.prescriptions);

  final List<String> prescriptions;
}

/// Module 12: reads the patient's own health profile from Firestore; every write goes
/// through FastAPI (audit, validation, risk re-score).
abstract interface class SettingsRepository {
  /// The stored health profile (D-25) merged with the user's date of birth and gender.
  Stream<OnboardingData?> profile(AppUser user);

  /// UC12.1. Returns true when the risk score was re-generated. [icNumber] (D-51) is
  /// sent only when given.
  Future<bool> updatePersonal({
    required String name,
    required DateTime dateOfBirth,
    required Gender gender,
    String? icNumber,
  });

  Future<void> updateContact(OnboardingData data);

  /// UC12.2. Returns true when the risk score was re-generated.
  Future<bool> updateHealth(OnboardingData data);

  Future<void> updateNotifications(NotificationPrefs prefs);

  /// UC12.3 (D-47): the file's bytes.
  Future<Uint8List> export(String format);

  /// UC12.4 (D-46). Throws [RecurringPrescriptionWarning] until acknowledged.
  Future<void> deleteAccount({bool acknowledgeRecurring = false});
}

class ApiSettingsRepository implements SettingsRepository {
  ApiSettingsRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  static Map<String, dynamic> _json(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is Map) return Map<String, dynamic>.from(v);
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }

  @override
  Stream<OnboardingData?> profile(AppUser user) =>
      _db.collection(Collections.healthProfiles).doc(user.uid).snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        return OnboardingData.fromStored(
          personalInfo: _json(d['personalInfo']),
          medicalHistory: _json(d['medicalHistory']),
          lifestyleFactors: _json(d['lifestyleFactors']),
          dateOfBirth: user.dateOfBirth,
          gender: user.gender,
        );
      });

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<bool> updatePersonal({
    required String name,
    required DateTime dateOfBirth,
    required Gender gender,
    String? icNumber,
  }) async {
    final res = await _api.updateProfile({
      'name': name.trim(),
      'dateOfBirth': _isoDate(dateOfBirth),
      'gender': gender.value,
      'icNumber': ?icNumber,
    });
    return res['rescored'] == true;
  }

  @override
  Future<void> updateContact(OnboardingData data) => _api.updateContact(data.toContactJson());

  @override
  Future<bool> updateHealth(OnboardingData data) async =>
      (await _api.updateHealthProfile(data.toHealthJson()))['rescored'] == true;

  @override
  Future<void> updateNotifications(NotificationPrefs prefs) =>
      _api.updateNotificationPrefs(prefs.toJson());

  @override
  Future<Uint8List> export(String format) async =>
      Uint8List.fromList(await _api.exportData(format));

  @override
  Future<void> deleteAccount({bool acknowledgeRecurring = false}) async {
    try {
      await _api.deleteAccount(acknowledgeRecurring: acknowledgeRecurring);
    } on ApiException catch (e) {
      if (e.code == 'ACTIVE_RECURRING_PRESCRIPTION') {
        final d = e.details;
        throw RecurringPrescriptionWarning([
          for (final p in (d is Map ? d['prescriptions'] as List? : null) ?? const []) '$p',
        ]);
      }
      rethrow;
    }
  }
}

/// Hands an exported file to the patient (D-47: Android share sheet).
abstract interface class FileSharer {
  Future<void> share(Uint8List bytes, {required String fileName, required String mimeType});
}

class ShareSheetFileSharer implements FileSharer {
  const ShareSheetFileSharer();

  @override
  Future<void> share(Uint8List bytes, {required String fileName, required String mimeType}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: 'My CareFlow health data',
      ),
    );
  }
}
