import 'package:geolocator/geolocator.dart';

/// Why location is or isn't available (so the app can say what to fix).
enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// D-62: the phone's GPS position, sent only for emergencies (never stored with readings).
abstract interface class LocationSource {
  /// Current position, or null when location is off, denied or slow. Asks for permission
  /// only when [ask] is true (SOS, the "share location" setting); readings never prompt.
  Future<Map<String, double>?> current({bool ask = false});

  Future<bool> granted();

  /// Asks for permission (once Android allows it) and reports the outcome.
  Future<LocationAccess> request();

  /// Opens the phone's location switch ([LocationAccess.serviceOff]) or the app's
  /// permission page ([LocationAccess.deniedForever]).
  Future<void> openSettings(LocationAccess access);
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  static const _timeout = Duration(seconds: 8);

  @override
  Future<bool> granted() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  @override
  Future<LocationAccess> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        _ => LocationAccess.denied,
      };
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  @override
  Future<Map<String, double>?> current({bool ask = false}) async {
    try {
      if (ask) {
        if (await request() != LocationAccess.granted) return null;
      } else if (!await granted() || !await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(_timeout);
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      return pos == null ? null : {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (_) {
      return null; // location must never block a reading or an SOS
    }
  }
}

/// Tests and the web portal: no location.
class NoLocationSource implements LocationSource {
  const NoLocationSource();

  @override
  Future<Map<String, double>?> current({bool ask = false}) async => null;

  @override
  Future<bool> granted() async => false;

  @override
  Future<LocationAccess> request() async => LocationAccess.denied;

  @override
  Future<void> openSettings(LocationAccess access) async {}
}

/// What to tell the patient when location isn't available, and the button label.
(String, String?) locationAdvice(LocationAccess access) => switch (access) {
  LocationAccess.granted => ('Location is on.', null),
  LocationAccess.serviceOff => (
    'Your phone\'s location (GPS) is turned off. Turn it on so family can find you.',
    'Turn on location',
  ),
  LocationAccess.deniedForever => (
    'Location permission was refused. Allow it for CareFlow in the phone\'s app settings.',
    'Open app settings',
  ),
  LocationAccess.denied => ('Location permission was not allowed.', null),
};
