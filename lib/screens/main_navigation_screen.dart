import 'package:flutter/material.dart';
import 'package:scribesync/screens/homeScreen.dart';
import 'package:scribesync/screens/recordings_screen.dart';
import 'package:scribesync/screens/academyPlanner.dart';
import 'package:scribesync/screens/settings.dart';

const Color primaryColor = Color(0xFF1E3F1F);
const Color secondaryColor = Color(0xFF2E6531);
const Color accentColor = Colors.white;
const Color highlightColor = Color(0xFF50AF53);

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const RecordingsScreen(),
    const AcademicPlannerScreen(),
    const SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: secondaryColor,
        selectedItemColor: accentColor,
        unselectedItemColor: Colors.white54,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.note),
            label: 'Notes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'Recordings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: 'Plans',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
} 