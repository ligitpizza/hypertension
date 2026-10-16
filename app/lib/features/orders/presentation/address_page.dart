import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../shared/services/api/api_client.dart';
import '../../auth/state/auth_providers.dart';
import '../../family/data/location_source.dart';
import '../../family/state/family_providers.dart';
import '../state/orders_providers.dart';

/// D-69: a picked delivery address.
typedef PickedAddress = ({String address, double lat, double lng});

/// Map point -> street address with Android's built-in geocoder (free, no API key).
typedef ReverseGeocoder = Future<String?> Function(double lat, double lng);

final reverseGeocoderProvider = Provider<ReverseGeocoder>(
  (ref) => (lat, lng) async {
    if (kIsWeb) return null;
    try {
      final places = await geo.Geocoding().placemarkFromCoordinates(lat, lng);
      final p = places.firstOrNull;
      if (p == null) return null;
      final parts = [
        p.subThoroughfare,
        p.thoroughfare,
        p.subLocality,
        p.postalCode,
        p.locality,
        p.administrativeArea,
      ].whereType<String>().where((x) => x.trim().isNotEmpty).toSet();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null; // offline or no match: the patient types it
    }
  },
);

/// An interactive map whose pin moves with taps and drags; tests swap in a placeholder.
typedef PickerMapBuilder =
    Widget Function(double lat, double lng, void Function(double lat, double lng) onMoved);

final pickerMapBuilderProvider = Provider<PickerMapBuilder>(
  (ref) =>
      (lat, lng, onMoved) => GoogleMap(
        key: ValueKey('picker-$lat-$lng'),
        initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 16),
        onTap: (p) => onMoved(p.latitude, p.longitude),
        markers: {
          Marker(
            markerId: const MarkerId('delivery'),
            position: LatLng(lat, lng),
            draggable: true,
            onDragEnd: (p) => onMoved(p.latitude, p.longitude),
          ),
        },
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      ),
);

/// Kuala Lumpur, shown until the patient shares or picks a location.
const _fallback = (lat: 3.1390, lng: 101.6869);

/// Pick a delivery address: "Use my current location" or move the pin; the text is filled
/// from the map point and stays editable. [saveToProfile] stores it as the patient's
/// address (Settings); otherwise the result is returned to the caller (checkout).
class AddressPage extends ConsumerStatefulWidget {
  const AddressPage({super.key, this.saveToProfile = true, this.initial});

  final bool saveToProfile;
  final PickedAddress? initial;

  @override
  ConsumerState<AddressPage> createState() => _AddressPageState();
}

class _AddressPageState extends ConsumerState<AddressPage> {
  final _text = TextEditingController();
  double? _lat;
  double? _lng;
  bool _busy = false;
  bool _seeded = false;
  String? _note;
  LocationAccess? _fix;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    final given = widget.initial;
    final me = ref.read(currentUserProvider).value;
    if (given != null) {
      _text.text = given.address;
      _lat = given.lat;
      _lng = given.lng;
    } else if (me?.address != null) {
      _text.text = me!.address!;
      _lat = me.addressLat;
      _lng = me.addressLng;
    }
  }

  Future<void> _moved(double lat, double lng) async {
    setState(() {
      _lat = lat;
      _lng = lng;
    });
    final text = await ref.read(reverseGeocoderProvider)(lat, lng);
    if (mounted && text != null) setState(() => _text.text = text);
  }

  Future<void> _useCurrent() async {
    final source = ref.read(locationSourceProvider);
    setState(() {
      _busy = true;
      _note = null;
      _fix = null;
    });
    final access = await source.request();
    final pos = access == LocationAccess.granted ? await source.current(ask: true) : null;
    if (!mounted) return;
    setState(() => _busy = false);
    if (pos == null) {
      final (text, action) = access == LocationAccess.granted
          ? ("Couldn't get a GPS fix. Move the pin instead.", null)
          : locationAdvice(access);
      setState(() {
        _note = text;
        _fix = action == null ? null : access;
      });
      return;
    }
    await _moved(pos['lat']!, pos['lng']!);
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.length < 5 || _lat == null || _lng == null) {
      setState(() => _note = 'Set the pin on the map and check the address text.');
      return;
    }
    final picked = (address: text, lat: _lat!, lng: _lng!);
    if (!widget.saveToProfile) {
      Navigator.of(context).pop(picked);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(ordersRepositoryProvider).saveAddress(text, lat: _lat, lng: _lng);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Delivery address saved.')));
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      setState(() => _note = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _seed();
    final map = ref.watch(pickerMapBuilderProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery address')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: map(_lat ?? _fallback.lat, _lng ?? _fallback.lng, _moved),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _lat == null
                ? 'Tap the map or use your current location to place the pin.'
                : 'Drag the pin or tap the map to adjust.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('address-current'),
            onPressed: _busy
                ? null
                : _fix != null
                ? () => ref.read(locationSourceProvider).openSettings(_fix!)
                : _useCurrent,
            icon: const Icon(Icons.my_location),
            label: Text(_fix != null ? locationAdvice(_fix!).$2! : 'Use my current location'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('address-text'),
            controller: _text,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Address',
              helperText: 'Filled from the map; add a unit number or landmark if needed.',
              border: OutlineInputBorder(),
            ),
          ),
          if (_note != null)
            Text(_note!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('address-save'),
            onPressed: _busy ? null : _save,
            child: Text(widget.saveToProfile ? 'Save address' : 'Use this address'),
          ),
        ],
      ),
    );
  }
}

/// D-70: an embedded map of a chosen point with "Use my current location" and
/// "Pick on map" (checkout drop-off, emergency fallback location).
class LocationMapCard extends ConsumerWidget {
  const LocationMapCard({
    super.key,
    required this.title,
    required this.lat,
    required this.lng,
    required this.onUseCurrent,
    required this.onPickOnMap,
    this.subtitle,
    this.busy = false,
    this.useCurrentKey = const Key('use-location'),
    this.useCurrentLabel = 'Use my current location',
  });

  final String title;
  final String? subtitle;
  final double? lat;
  final double? lng;
  final VoidCallback? onUseCurrent;
  final VoidCallback? onPickOnMap;
  final bool busy;
  final Key useCurrentKey;
  final String useCurrentLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final map = ref.watch(mapBuilderProvider);
    final has = lat != null && lng != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 170,
            child: has
                ? map(lat!, lng!, title)
                : ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_off_outlined, color: theme.colorScheme.outline),
                        const SizedBox(height: 4),
                        const Text('No location set yet'),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  has ? Icons.location_on : Icons.location_off_outlined,
                  color: has ? theme.colorScheme.primary : null,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(subtitle!, style: theme.textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        key: useCurrentKey,
                        onPressed: onUseCurrent,
                        icon: const Icon(Icons.my_location),
                        label: Text(useCurrentLabel),
                      ),
                TextButton.icon(
                  key: const Key('pick-on-map'),
                  onPressed: onPickOnMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Pick on map'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
