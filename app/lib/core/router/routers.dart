import 'package:go_router/go_router.dart';

import '../../shared/widgets/walking_skeleton_page.dart';

// One router per entrypoint; each registers only its own roles' routes
// (docs/05 "Routes per entrypoint", NFR-3.2). Increment 0 has a single
// placeholder route; auth redirects arrive with Module 1 (Increment 1).

GoRouter buildPatientRouter() => GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const WalkingSkeletonPage(title: 'CareFlow'),
        ),
      ],
    );

GoRouter buildFamilyRouter() => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const WalkingSkeletonPage(title: 'CareFlow Family'),
        ),
      ],
    );

GoRouter buildStaffRouter() => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => const WalkingSkeletonPage(title: 'CareFlow Staff Portal'),
        ),
      ],
    );
