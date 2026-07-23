import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/theme_providers.dart';
import 'widgets/splash_overlay.dart';

class NewsupApp extends ConsumerWidget {
  const NewsupApp({super.key});

  /// Lets services outside the widget tree (e.g. [PushNotificationService])
  /// surface a SnackBar — such as an "update available" prompt — without
  /// needing a BuildContext of their own.
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(appThemeDataProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'TruthLens India',
      debugShowCheckedModeBanner: false,
      theme: themeData.toThemeData(),
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const SplashOverlay(),
          ],
        );
      },
    );
  }
}
