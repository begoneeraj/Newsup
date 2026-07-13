import 'package:flutter/material.dart';

import 'crisis_tracker_list_screen.dart';
import 'fact_check_list_screen.dart';
import 'govt_promise_list_screen.dart';
import 'science_data_list_screen.dart';
import 'slow_crisis_list_screen.dart';

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
    GovtPromiseListScreen.new,
    ScienceDataListScreen.new,
    SlowCrisisListScreen.new,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        // Only build a tab's screen (and fire its providers) once it has
        // actually been visited - IndexedStack builds every child eagerly
        // regardless of visibility, so without this every provider on every
        // tab would query Supabase on cold start instead of on first visit.
        children: [
          for (var i = 0; i < _tabBuilders.length; i++)
            if (_visitedTabs.contains(i)) _tabBuilders[i]() else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() {
          _tabIndex = index;
          _visitedTabs.add(index);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Fact Checks',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'Crisis Tracker',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake),
            label: 'Promises',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Science & Data',
          ),
          NavigationDestination(
            icon: Icon(Icons.trending_down_outlined),
            selectedIcon: Icon(Icons.trending_down),
            label: 'Slow Crises',
          ),
        ],
      ),
    );
  }
}
