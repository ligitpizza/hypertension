import 'package:geolocator/geolocator.dart';

/// D-62: the phone's GPS position, sent only for emergencies (never stored with readings).
abstract interface class LocationSource {
  /// Current position, or null when location is off, denied or slow. Asks for permission
  /// only when [ask] is true (SOS, the "share location" setting); readings never prompt.
  Future<Map<String, double>?> current({bool ask = false});

  Future<bool> granted();
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  static const _timeout = Duration(seconds: 6);

  @override
  Future<bool> granted() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  @override
  Future<Map<String, double>?> current({bool ask = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) p = await Geolocator.requestPermission();
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return null;
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
}
