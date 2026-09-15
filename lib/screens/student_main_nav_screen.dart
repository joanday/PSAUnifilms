import 'package:flutter/material.dart';
import 'student_home_screen.dart';
import 'watchlist_screen.dart';
import 'submit_screen.dart';
import 'profile_screen.dart';

class StudentMainNavScreen extends StatefulWidget {
  const StudentMainNavScreen({super.key});

  @override
  State<StudentMainNavScreen> createState() => _StudentMainNavScreenState();
}

class _StudentMainNavScreenState extends State<StudentMainNavScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    StudentHomeScreen(),
    WatchlistScreen(),
    SubmitScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D1F17),
          border: Border(top: BorderSide(color: Color(0xFF1E3528), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: const Color(0xFF0D1F17),
          selectedItemColor: const Color(0xFF4CAF50),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.list_outlined),
                activeIcon: Icon(Icons.list_rounded),
                label: 'Watchlist'),
            BottomNavigationBarItem(
                icon: Icon(Icons.add_circle_outline),
                activeIcon: Icon(Icons.add_circle_rounded),
                label: 'Submit'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person_rounded),
                label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
