// lib/screens/main_navigation.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// removed: import 'package:provider/provider.dart';

import 'package:outings_app/features/messages/messages_repository.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({
    super.key,
    required this.navigationShell,
    required this.currentLocation,
  });

  final StatefulNavigationShell navigationShell;
  final String currentLocation;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  Offset? _fabPos;
  final MessagesRepository _repo = MessagesRepository();

  List<BottomNavigationBarItem> _itemsWithBadge(int unread) {
    final cs = Theme.of(context).colorScheme;
    final badgeBg = cs.error;
    final badgeFg = cs.onError;

    return <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.home, key: Key('tab-home')),
        label: 'Home',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.explore, key: Key('tab-discover')),
        label: 'Discover',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.event, key: Key('tab-plan')),
        label: 'Plan',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.group, key: Key('tab-groups')),
        label: 'Groups',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.calendar_today, key: Key('tab-calendar')),
        label: 'Calendar',
      ),
      BottomNavigationBarItem(
        label: 'Messages',
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.message, key: Key('tab-messages')),
            if (unread > 0)
              Positioned(
                right: -6,
                top: -3,
                child: Semantics(
                  label: 'Unread messages: ${unread > 99 ? '99+' : '$unread'}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 16,
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: badgeFg,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(index, initialLocation: true);
    const messagesTabIndex = 5;
    if (index != messagesTabIndex) _repo.setActivePeer(null);
  }

  @override
  Widget build(BuildContext context) {
    final bool isOnHome = widget.currentLocation.startsWith('/home');

    final bool onChatRoute = widget.currentLocation.startsWith(
      '/messages/chat/',
    );
    if (!onChatRoute && _repo.activePeer.value != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _repo.setActivePeer(null),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        const double margin = 16;
        const double fabHeight = 48;
        final double reservedBottom = 56 + media.padding.bottom + margin;

        _fabPos ??= Offset(
          constraints.maxWidth - margin - 140,
          constraints.maxHeight - reservedBottom - fabHeight,
        );
        Offset _clamp(Offset p) {
          final dx = p.dx.clamp(margin, constraints.maxWidth - margin - 140);
          final dy = p.dy.clamp(
            media.padding.top + margin,
            constraints.maxHeight - reservedBottom - fabHeight,
          );
          return Offset(dx.toDouble(), dy.toDouble());
        }

        return ValueListenableBuilder<int>(
          valueListenable: _repo.unseenTotal,
          builder: (context, unread, _) {
            final cs = Theme.of(context).colorScheme;
            final body = Scaffold(
              body: SafeArea(child: widget.navigationShell),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: widget.navigationShell.currentIndex,
                onTap: _onTap,
                items: _itemsWithBadge(unread),
                type: BottomNavigationBarType.fixed,
                selectedItemColor: cs.primary, // ← theme-driven
              ),
            );

            if (isOnHome) return body;

            final draggableHome = Positioned(
              left: _fabPos!.dx,
              top: _fabPos!.dy,
              child: GestureDetector(
                onPanStart: (_) => FocusScope.of(context).unfocus(),
                onPanUpdate: (details) =>
                    setState(() => _fabPos = _clamp(_fabPos! + details.delta)),
                child: Material(
                  elevation: 6,
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => context.go('/home'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Home',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );

            return Stack(children: [body, if (!isOnHome) draggableHome]);
          },
        );
      },
    );
  }
}
