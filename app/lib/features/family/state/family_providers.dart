import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/providers/api_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../data/family_repository.dart';
import '../data/location_source.dart';

Duration? _noRetry(int _, Object _) => null;

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => FirebaseFamilyRepository(FirebaseFirestore.instance, ref.watch(apiClientProvider)),
);

/// D-62: GPS on Android only (the staff portal and tests have none).
final locationSourceProvider = Provider<LocationSource>(
  (ref) => kIsWeb ? const NoLocationSource() : const GeolocatorLocationSource(),
);

/// The embedded map (google_maps_flutter); tests swap in a placeholder.
typedef MapBuilder = Widget Function(double lat, double lng, String label);

final mapBuilderProvider = Provider<MapBuilder>(
  (ref) =>
      (lat, lng, label) => GoogleMap(
        initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 15),
        markers: {
          Marker(
            markerId: const MarkerId('patient'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(title: label),
          ),
        },
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      ),
);

Stream<T> _forUser<T>(Ref ref, Stream<T> Function(String uid) build, T empty) {
  final uid = ref.watch(authUidProvider).value;
  return uid == null ? Stream.value(empty) : build(uid);
}

// ---- family member app ----

/// The patient this family member follows (null while not linked; UC15.1 E1).
final linkedPatientIdProvider = StreamProvider<String?>((ref) {
  final repo = ref.watch(familyRepositoryProvider);
  return _forUser<String?>(ref, repo.linkedPatientId, null);
}, retry: _noRetry);

final myPendingLinkProvider = StreamProvider<LinkRequest?>((ref) {
  final repo = ref.watch(familyRepositoryProvider);
  return _forUser<LinkRequest?>(ref, repo.myPendingRequest, null);
}, retry: _noRetry);

final linkedPersonProvider = StreamProvider.family<LinkedPerson?, String>(
  (ref, uid) => ref.watch(familyRepositoryProvider).person(uid),
  retry: _noRetry,
);

final myEmergencyAlertsProvider = StreamProvider<List<EmergencyAlert>>((ref) {
  final repo = ref.watch(familyRepositoryProvider);
  return _forUser(ref, repo.myAlerts, const <EmergencyAlert>[]);
}, retry: _noRetry);

// ---- patient app ----

final pendingFamilyRequestsProvider = StreamProvider<List<LinkRequest>>((ref) {
  final repo = ref.watch(familyRepositoryProvider);
  return _forUser(ref, repo.pendingForPatient, const <LinkRequest>[]);
}, retry: _noRetry);

final linkedFamilyProvider = StreamProvider<List<LinkedPerson>>((ref) {
  final repo = ref.watch(familyRepositoryProvider);
  return _forUser(ref, repo.linkedFamily, const <LinkedPerson>[]);
}, retry: _noRetry);

/// Opens Google Maps (navigation, nearby hospitals) outside the app; tests record the URL.
final openUrlProvider = Provider<Future<bool> Function(Uri url)>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// Google Maps directions to a point (no API key; opens the Maps app).
Uri directionsUrl(double lat, double lng) =>
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

/// Hospitals near a point, or near the phone when unknown (Maps search; no Places API).
Uri hospitalsNearUrl(double? lat, double? lng) => Uri.parse(
  lat == null || lng == null
      ? 'https://www.google.com/maps/search/hospital'
      : 'https://www.google.com/maps/search/hospital/@$lat,$lng,14z',
);
