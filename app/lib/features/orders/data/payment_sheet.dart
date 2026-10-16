import 'package:flutter_stripe/flutter_stripe.dart';

/// Outcome of Stripe's PaymentSheet (UC13.3).
enum SheetOutcome { completed, cancelled, failed }

class SheetResult {
  const SheetResult(this.outcome, [this.message]);
  final SheetOutcome outcome;
  final String? message;
}

/// Opens Stripe's hosted PaymentSheet: the card is entered in Stripe's UI, so CareFlow
/// never sees card data (NFR-2.3, D-66).
abstract interface class PaymentSheetLauncher {
  Future<SheetResult> present({required String publishableKey, required String clientSecret});
}

class StripePaymentSheet implements PaymentSheetLauncher {
  @override
  Future<SheetResult> present({
    required String publishableKey,
    required String clientSecret,
  }) async {
    try {
      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'CareFlow',
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return const SheetResult(SheetOutcome.completed);
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return const SheetResult(SheetOutcome.cancelled);
      return SheetResult(SheetOutcome.failed, e.error.localizedMessage ?? e.error.message);
    }
  }
}
