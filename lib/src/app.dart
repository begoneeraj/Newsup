import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/theme_providers.dart';

class NewsupApp extends ConsumerWidget {
  const NewsupApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(appThemeDataProvider);

    return MaterialApp.router(
      title: 'Newsup',
      debugShowCheckedModeBanner: false,
      theme: themeData.toThemeData(),
      routerConfig: appRouter,
    );
  }
}
