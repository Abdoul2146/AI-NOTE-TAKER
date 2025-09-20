import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
// import 'package:scribesync/screens/homeScreen.dart';
// import 'package:scribesync/screens/academyPlanner.dart';
import 'package:scribesync/screens/signInScreen.dart';

// ... (rest of your color constants and widget definitions)

const Color primaryColor = Color(0xFF1E3F1F);
const Color secondaryColor = Color(0xFF2E6531);
const Color accentColor = Colors.white;
const Color highlightColor = Color(0xFF50AF53);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsSectionTitle('Account'),
              // _buildSettingsItem(
              //   title: 'Change Password',
              //   icon: Icons.lock,
              //   onTap: () {
              //     // TODO: Implement change password logic
              //   },
              // ),
              _buildSettingsItem(
                title: 'Log Out',
                icon: Icons.logout,
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SignInScreen(),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logout Successfull!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // The StreamBuilder in main.dart will automatically handle the navigation
                  // after the user signs out.
                },
              ),
              const SizedBox(height: 24),
              _buildSettingsSectionTitle('General'),
              _buildSettingsItem(
                title: 'Notifications',
                icon: Icons.notifications,
                trailing: Switch(
                  value: _notificationsEnabled,
                  onChanged: (bool value) {
                    setState(() {
                      _notificationsEnabled = value;
                      // TODO: Implement notification toggle logic
                    });
                  },
                  activeColor: highlightColor,
                ),
              ),
              // _buildSettingsItem(
              //   title: 'App Theme',
              //   icon: Icons.palette,
              //   onTap: () {
              //     // TODO: Implement theme selection logic
              //   },
              // ),
              // const SizedBox(height: 24),
              // _buildSettingsSectionTitle('About'),
              // _buildSettingsItem(
              //   title: 'Privacy Policy',
              //   icon: Icons.privacy_tip,
              //   onTap: () {
              //     // TODO: Navigate to privacy policy page
              //   },
              // ),
              // _buildSettingsItem(
              //   title: 'Terms of Service',
              //   icon: Icons.description,
              //   onTap: () {
              //     // TODO: Navigate to terms of service page
              //   },
              // ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: accentColor,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSettingsItem({
    required String title,
    String? subtitle,
    required IconData icon,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: secondaryColor,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          leading: Icon(icon, color: accentColor),
          title: Text(
            title,
            style: const TextStyle(
              color: accentColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle:
              subtitle != null
                  ? Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70),
                  )
                  : null,
          trailing:
              trailing ??
              const Icon(Icons.arrow_forward_ios, color: accentColor, size: 16),
          onTap: onTap,
        ),
      ),
    );
  }
}
