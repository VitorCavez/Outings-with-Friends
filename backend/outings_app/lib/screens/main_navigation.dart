import 'package:flutter/material.dart';
import '../features/plan/plan_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/groups/groups_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/messages/messages_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    PlanScreen(),
    DiscoverScreen(),
    GroupsScreen(),
    CalendarScreen(),
    MessagesScreen(),
  ];

  final List<BottomNavigationBarItem> _items = const [
    BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Plan'),
    BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
    BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Groups'),
    BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Calendar'),
    BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: _items,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.deepPurple,
      ),
    );
  }
}
