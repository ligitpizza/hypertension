import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/services/api/api_client.dart';
import '../../family/data/location_source.dart';
import '../../family/state/family_providers.dart';
import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';
import 'address_page.dart';

/// Fig 4.3.10.1 Order confirmation (UC13.2, UC13.3; FR-13.2). Insurance coverage is out of
/// scope (D-66), so the total is the medicine plus any delivery fee.
class OrderConfirmPage extends ConsumerStatefulWidget {
  const OrderConfirmPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderConfirmPage> createState() => _OrderConfirmPageState();
}

class _OrderConfirmPageState extends ConsumerState<OrderConfirmPage> {
  String? _method;
  final _address = TextEditingController();
  final _phone = TextEditingController();

  /// D-67: the drop-off point for the courier, from the phone's GPS.
  Map<String, double>? _location;
  bool _locating = false;
  String? _locationNote;
  LocationAccess? _locationFix;
  bool _busy = false;

  /// D-71: the courier's fee for the current drop-off (null until quoted).
  double? _quotedFee;
  bool _quoting = false;
  String? _quotedFor;
  String? _error;
  bool _seeded = false;

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _seed(MedicationOrder o, List<MedicationOrder> all) {
    if (_seeded) return;
    _seeded = true;
    _method = o.method;
    // Prefill: this order's address, else the saved delivery address (D-69), else the
    // last address the patient used.
    _address.text =
        o.deliveryAddress ??
        o.suggestedAddress ??
        all.map((x) => x.deliveryAddress).whereType<String>().firstOrNull ??
        '';
    _phone.text = o.deliveryPhone ?? o.suggestedPhone ?? '';
    // D-71: an order confirmed earlier keeps the fee it was quoted.
    if (o.method == homeDelivery && o.deliveryFee > 0) _quotedFee = o.deliveryFee;
    if (o.deliveryLat != null && o.deliveryLng != null) {
      _location = {'lat': o.deliveryLat!, 'lng': o.deliveryLng!};
    } else if (o.suggestedLat != null && o.suggestedLng != null) {
      _location = {'lat': o.suggestedLat!, 'lng': o.suggestedLng!};
    }
  }

  /// D-69: pick the drop-off on the map (address text filled from the pin).
  Future<void> _pickOnMap() async {
    final loc = _location;
    final picked = await Navigator.of(context).push<PickedAddress>(
      MaterialPageRoute(
        builder: (_) => AddressPage(
          saveToProfile: false,
          initial: loc == null
              ? null
              : (address: _address.text, lat: loc['lat']!, lng: loc['lng']!),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _address.text = picked.address;
      _location = {'lat': picked.lat, 'lng': picked.lng};
      _locationNote = null;
      _locationFix = null;
    });
    _requote();
  }

  /// D-71: ask the courier for this drop-off's fee (once per point).
  Future<void> _requote() async {
    final loc = _location;
    if (_method != homeDelivery || loc == null) return;
    final key = '${loc['lat']},${loc['lng']}';
    if (_quotedFor == key) return;
    setState(() {
      _quoting = true;
      _quotedFor = key;
    });
    try {
      final fee = await ref
          .read(ordersRepositoryProvider)
          .deliveryQuote(
            widget.orderId,
            address: _address.text.trim(),
            lat: loc['lat']!,
            lng: loc['lng']!,
          );
      if (mounted) setState(() => _quotedFee = fee);
    } catch (_) {
      if (mounted) setState(() => _quotedFor = null); // shown as an estimate; retried later
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _locate() async {
    final source = ref.read(locationSourceProvider);
    setState(() {
      _locating = true;
      _locationNote = null;
      _locationFix = null;
    });
    final access = await source.request();
    final pos = access == LocationAccess.granted ? await source.current(ask: true) : null;
    if (!mounted) return;
    setState(() {
      _locating = false;
      _location = pos ?? _location;
      if (pos == null) {
        final (text, action) = access == LocationAccess.granted
            ? ("Couldn't get a GPS fix. Try again near a window.", null)
            : locationAdvice(access);
        _locationNote = text;
        _locationFix = action == null ? null : access;
      }
    });
    _requote();
  }

  Future<void> _confirm() async {
    final method = _method;
    if (method == null) return;
    final home = method == homeDelivery;
    if (home && _address.text.trim().isEmpty) {
      setState(() => _error = 'Enter the delivery address.');
      return;
    }
    if (home && _location == null) {
      setState(() => _error = 'Share your current location so the courier can find you.');
      return;
    }
    final phoneError = home ? Validators.phone(_phone.text) : null;
    if (phoneError != null) {
      setState(() => _error = 'Contact number: $phoneError');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ordersRepositoryProvider)
          .confirm(
            widget.orderId,
            method,
            address: home ? _address.text.trim() : null,
            lat: home ? _location!['lat'] : null,
            lng: home ? _location!['lng'] : null,
            phone: home ? _phone.text.trim() : null,
          );
      ref.invalidate(myOrdersProvider);
      if (mounted) context.pushReplacement('/orders/${widget.orderId}/pay');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not confirm the order. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip this month?'),
        content: const Text(
          "We won't prepare this month's refill. Your next order arrives next month.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm-skip'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(ordersRepositoryProvider).skip(widget.orderId);
      ref
        ..invalidate(myOrdersProvider)
        ..invalidate(orderProvider(widget.orderId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skipped. You can still confirm it this month.')),
        );
        context.pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    final all = ref.watch(myOrdersProvider).value ?? const <MedicationOrder>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Order confirmation')),
      body: order.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(orderProvider(widget.orderId)),
            child: const Text('Could not load the order. Retry'),
          ),
        ),
        data: (o) {
          _seed(o, all);
          return _body(context, o);
        },
      ),
    );
  }

  Widget _body(BuildContext context, MedicationOrder o) {
    final theme = Theme.of(context);
    final open =
        o.status == Fulfilment.awaitingConfirmation ||
        o.status == Fulfilment.skipped ||
        o.status == Fulfilment.awaitingPayment;
    // D-71: the courier's quote once the drop-off is known; the flat fee until then.
    final fee = _method == homeDelivery ? (_quotedFee ?? deliveryFeeRm) : 0.0;
    final amount = o.amount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.medication_outlined, color: theme.colorScheme.primary),
                  ),
                  title: Text('Confirm monthly order', style: theme.textTheme.titleMedium),
                  subtitle: Text('${cycleLabel(o.cycleDate)} · review and confirm your refill.'),
                ),
                const Divider(),
                if (o.items.isNotEmpty)
                  // D-69: each prescribed medicine with quantity x unit price.
                  for (final i in o.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(i.label, style: theme.textTheme.titleSmall),
                                Text(
                                  '${i.dose}, ${frequencyLabel(i.frequency).toLowerCase()} · '
                                  '${i.quantity} × ${rm(i.unitPrice)}',
                                ),
                              ],
                            ),
                          ),
                          Text(rm(i.lineTotal), style: theme.textTheme.titleMedium),
                        ],
                      ),
                    )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.medicationDetails, style: theme.textTheme.titleSmall),
                            const Text('30-day supply'),
                          ],
                        ),
                      ),
                      Text(
                        amount == null ? '—' : rm(amount),
                        key: const Key('item-price'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (amount == null)
                  Container(
                    key: const Key('not-priced'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "The pharmacy hasn't priced this medicine yet. We'll notify you when "
                      "it's ready to confirm.",
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _row('Subtotal', rm(amount)),
                        if (fee > 0)
                          _row(
                            _quotedFee == null
                                ? 'Delivery (estimate until your drop-off is set)'
                                : 'Delivery (${o.courierBrand} quote)',
                            _quoting ? '…' : rm(fee),
                            key: const Key('delivery-fee'),
                          ),
                        const Divider(),
                        _row(
                          'Estimated total',
                          rm(amount + fee),
                          key: const Key('order-total'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Select delivery method', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        _MethodCard(
          key: const Key('method-collection'),
          icon: Icons.storefront_outlined,
          title: 'Self-collection',
          subtitle: 'Pick up at $pharmacyName',
          selected: _method == selfCollection,
          onTap: open ? () => setState(() => _method = selfCollection) : null,
        ),
        _MethodCard(
          key: const Key('method-delivery'),
          icon: Icons.local_shipping_outlined,
          title: 'Home delivery',
          subtitle: _quotedFee == null
              ? 'Courier fee from ${o.courierBrand} · quoted for your address'
              : '+${rm(_quotedFee!)} · delivered by ${o.courierBrand}',
          selected: _method == homeDelivery,
          onTap: open
              ? () {
                  setState(() => _method = homeDelivery);
                  _requote();
                }
              : null,
        ),
        if (_method == homeDelivery) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('delivery-address'),
            controller: _address,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Delivery address',
              border: OutlineInputBorder(),
            ),
          ),
          // D-67/D-70: the courier needs the exact drop-off point; shown on a map.
          LocationMapCard(
            key: const Key('delivery-location'),
            title: _location == null
                ? 'Share your location for the courier'
                : 'Location shared for the courier',
            subtitle:
                _locationNote ??
                (_location == null
                    ? "Use your current location when you're at the address, or pick it on "
                          'the map.'
                    : 'Drag the pin with "Pick on map" if it is not quite right.'),
            lat: _location?['lat'],
            lng: _location?['lng'],
            busy: _locating,
            useCurrentLabel: _locationFix != null
                ? locationAdvice(_locationFix!).$2!
                : _location == null
                ? 'Use my current location'
                : 'Update',
            onUseCurrent: _locationFix != null
                ? () => ref.read(locationSourceProvider).openSettings(_locationFix!)
                : _locate,
            onPickOnMap: _pickOnMap,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('delivery-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 20,
            decoration: InputDecoration(
              labelText: 'Contact number for the courier',
              helperText: '${o.courierBrand} only gets your first name and this number.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('confirm-order'),
          onPressed: !open || _busy || _method == null || amount == null ? null : _confirm,
          child: Text(_busy ? 'Please wait…' : 'Confirm order'),
        ),
        if (o.status == Fulfilment.awaitingConfirmation || o.status == Fulfilment.awaitingPayment)
          TextButton(
            key: const Key('skip-order'),
            onPressed: _busy ? null : _skip,
            child: const Text('Skip this month'),
          ),
        if (o.status == Fulfilment.skipped)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'You skipped this month. You can still confirm it if you change your mind.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value, {Key? key, TextStyle? style}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, key: key, style: style),
      ],
    ),
  );
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: 1.5),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(icon, color: scheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? scheme.primary : null,
        ),
      ),
    );
  }
}
