import 'package:go_router/go_router.dart';

import '../screens/crisis_tracker_detail_screen.dart';
import '../screens/fact_check_detail_screen.dart';
import '../screens/home_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/fact-check/:id',
      builder: (context, state) => FactCheckDetailScreen(
        id: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/crisis/:id',
      builder: (context, state) => CrisisTrackerDetailScreen(
        id: state.pathParameters['id']!,
      ),
    ),
  ],
);
