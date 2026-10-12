// Staff Web Portal (Flutter Web). Run: flutter run -d chrome -t lib/main_staff.dart
import 'core/app.dart';
import 'core/bootstrap.dart';
import 'core/router/routers.dart';
import 'firebase_options_staff.dart';

Future<void> main() => bootstrap(
  flavor: AppFlavor.staff,
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  app: () => CareFlowApp(title: 'CareFlow Staff Portal', router: staffRouterProvider),
);
