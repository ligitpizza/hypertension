import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../data/order_models.dart';
import '../data/payment_sheet.dart';
import '../state/orders_providers.dart';

/// Fig 4.3.10.2 Secure payment (UC13.3; FR-13.3; NFR-2.3; D-66). With Stripe test keys the
/// card is entered in Stripe's PaymentSheet; without them a simulated card form stands in
/// (test numbers only).
class OrderPayPage extends ConsumerStatefulWidget {
  const OrderPayPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderPayPage> createState() => _OrderPayPageState();
}

class _OrderPayPageState extends ConsumerState<OrderPayPage> {
  final _card = TextEditingController(text: '4242 4242 4242 4242');
  PaymentStart? _start;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _card.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final s = await ref.read(ordersRepositoryProvider).startPayment(widget.orderId);
      if (mounted) setState(() => _start = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start the payment.');
    }
  }

  Future<void> _pay() async {
    final start = _start;
    if (start == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(ordersRepositoryProvider);
    try {
      PaymentResult result;
      if (start.isFake) {
        result = await repo.payFake(widget.orderId, _card.text);
      } else {
        final sheet = await ref
            .read(paymentSheetProvider)
            .present(publishableKey: start.publishableKey, clientSecret: start.clientSecret);
        if (sheet.outcome == SheetOutcome.cancelled) return;
        if (sheet.outcome == SheetOutcome.failed) {
          setState(() => _error = sheet.message ?? 'The payment did not go through.');
          return;
        }
        // The webhook may land a moment later; ask the server a few times.
        result = await repo.refreshPayment(widget.orderId);
        for (var i = 0; i < 3 && result.result == 'pending'; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          result = await repo.refreshPayment(widget.orderId);
        }
      }
      if (!mounted) return;
      if (result.paid) {
        ref
          ..invalidate(myOrdersProvider)
          ..invalidate(orderProvider(widget.orderId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment received. Receipt saved to your records.')),
        );
        context.pushReplacement('/orders/${widget.orderId}/track');
      } else if (result.result == 'failed') {
        // UC13.3 E1: try again with another card.
        setState(
          () =>
              _error = '${result.message ?? 'Your card was declined.'} Try another payment method.',
        );
      } else {
        setState(() => _error = 'The payment is still processing. Check back in a moment.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId)).value;
    final theme = Theme.of(context);
    final start = _start;
    final total = order?.total ?? start?.amount;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Payment method', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (start == null && _error == null)
            const Center(child: CircularProgressIndicator())
          else if (start != null && start.isFake)
            Card(
              key: const Key('fake-card-form'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('card-number'),
                      controller: _card,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                      decoration: const InputDecoration(
                        labelText: 'Card number',
                        prefixIcon: Icon(Icons.credit_card),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Simulated payment (test mode). 4242 4242 4242 4242 succeeds; '
                      '4000 0000 0000 0002 is declined. Never enter a real card.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          else if (start != null)
            Card(
              key: const Key('stripe-method'),
              child: const ListTile(
                leading: Icon(Icons.credit_card),
                title: Text('Card, via Stripe'),
                subtitle: Text("You'll enter your card in Stripe's secure form (test mode)."),
              ),
            ),
          const SizedBox(height: 16),
          if (order != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order summary', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _row('Medications', order.amount == null ? '—' : rm(order.amount!)),
                    if (order.isDelivery) _row('Delivery', rm(order.deliveryFee)),
                    const Divider(),
                    _row(
                      'Total',
                      total == null ? '—' : rm(total),
                      style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                      key: const Key('pay-total'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 16),
                        const SizedBox(width: 6),
                        Text('Payments are secure and encrypted', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const Key('pay-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            if (start == null)
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  _prepare();
                },
                child: const Text('Retry'),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          key: const Key('pay-button'),
          onPressed: start == null || _busy ? null : _pay,
          icon: const Icon(Icons.lock_outline),
          label: Text(_busy ? 'Processing…' : 'Pay ${total == null ? '' : rm(total)}'.trim()),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {TextStyle? style, Key? key}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, key: key, style: style),
      ],
    ),
  );
}
