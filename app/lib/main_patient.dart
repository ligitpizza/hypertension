// Patient mobile app (Android). Run: flutter run --flavor patient -t lib/main_patient.dart
import 'core/app.dart';
import 'core/bootstrap.dart';
import 'core/router/routers.dart';
import 'firebase_options_patient.dart';

Future<void> main() => bootstrap(
      flavor: AppFlavor.patient,
      firebaseOptions: DefaultFirebaseOptions.currentPlatform,
      app: () => CareFlowApp(title: 'CareFlow', router: buildPatientRouter()),
    );
