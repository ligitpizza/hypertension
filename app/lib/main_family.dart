// Family Member mobile app (Android). Run: flutter run --flavor family -t lib/main_family.dart
import 'core/app.dart';
import 'core/bootstrap.dart';
import 'core/router/routers.dart';
import 'firebase_options_family.dart';

Future<void> main() => bootstrap(
  flavor: AppFlavor.family,
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  app: () => CareFlowApp(title: 'Harvey Family', router: familyRouterProvider),
);
