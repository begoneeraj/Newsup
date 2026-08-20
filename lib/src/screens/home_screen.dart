import 'package:flutter/material.dart';

import '../theme/app_theme_data.dart';
import '../widgets/floating_bottom_nav.dart';
import 'crisis_tracker_list_screen.dart';
import 'fact_check_list_screen.dart';
import 'saved_fact_checks_screen.dart';
import 'slow_crisis_list_screen.dart';
import 'underreported_topic_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  final Set<int> _visitedTabs = {0};

  static const _tabBuilders = [
    FactCheckListScreen.new,
    CrisisTrackerListScreen.new,
    SlowCrisisListScreen.new,
    UnderreportedTopicListScreen.new,
    SavedFactChecksScreen.new,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        // A crossfading Stack instead of IndexedStack's instant swap: every
        // visited tab stays mounted (so its providers/scroll state survive
        // switching away and back) but only the active one is opaque and
        // hit-testable.
        children: [
          for (var i = 0; i < _tabBuilders.length; i++)
            if (_visitedTabs.contains(i))
              IgnorePointer(
                ignoring: i != _tabIndex,
                child: AnimatedOpacity(
                  opacity: i == _tabIndex ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: _tabBuilders[i](),
                ),
              ),
        ],
      ),
      bottomNavigationBar: FloatingBottomNav(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() {
          _tabIndex = index;
          _visitedTabs.add(index);
        }),
        destinations: const [
          NavDestination(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'Spotlight',
            color: AppSectionColors.home,
          ),
          NavDestination(
            icon: Icons.local_fire_department_outlined,
            selectedIcon: Icons.local_fire_department_rounded,
            label: 'Crisis Tracker',
            color: AppSectionColors.crisis,
          ),
          NavDestination(
            icon: Icons.trending_down_rounded,
            selectedIcon: Icons.trending_down_rounded,
            label: 'Silent Signals',
            color: AppSectionColors.slowCrisis,
          ),
          NavDestination(
            icon: Icons.visibility_off_outlined,
            selectedIcon: Icons.visibility_off_rounded,
            label: 'Overlooked',
            color: AppSectionColors.underreported,
          ),
          NavDestination(
            icon: Icons.bookmark_border_rounded,
            selectedIcon: Icons.bookmark_rounded,
            label: 'Saved',
            color: AppSectionColors.saved,
          ),
        ],
      ),
    );
  }
}
