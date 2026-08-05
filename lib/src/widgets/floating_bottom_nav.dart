import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

class NavDestination {
  const NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Each destination carries its own section-identity accent (see
  /// AppSectionColors) rather than one shared app accent, so the active
  /// tab always reads as "this section" at a glance.
  final Color color;
}

/// Floating frosted-glass pill bottom nav. Surface-level-2 @ 90% opacity +
/// blur(20). Inactive tabs are icon-only; the active tab shows icon+label.
/// Wrapped in its own SafeArea + fixed bottom margin so it always sits
/// clear of the system nav bar and never overlaps page content.
class FloatingBottomNav extends ConsumerWidget {
  const FloatingBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavDestination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A4FFF).withValues(alpha: 0.25),
                blurRadius: 28,
                spreadRadius: -4,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: theme.surfaceVariant.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _NavItem(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          onTap: () => onDestinationSelected(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  static const _muted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final color = selected ? destination.color : _muted;

    // Fixed-height column: icon, then an always-reserved label slot (so
    // switching tabs never resizes the row).
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 24,
                color: color,
                shadows: selected
                    ? [Shadow(color: destination.color.withValues(alpha: 0.75), blurRadius: 14)]
                    : null,
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 14,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: selected ? 1 : 0,
                    child: Text(
                      destination.label,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
