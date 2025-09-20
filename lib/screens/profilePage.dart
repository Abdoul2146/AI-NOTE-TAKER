import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

const Color primaryColor = Color(0xFF1E3F1F);
const Color secondaryColor = Color(0xFF2E6531);
const Color accentColor = Colors.white;
const Color highlightColor = Color(0xFF50AF53);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<String?> _fetchName(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data()?['name'] as String?;
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat('dd MMM yyyy, HH:mm').format(dateTime);
  }

  String _initialsFrom(String? name, String? email) {
    final src = (name?.trim().isNotEmpty == true ? name!.trim() : (email ?? '')).trim();
    if (src.isEmpty) return '?';
    final parts = src.split(' ');
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
        title: const Text('Profile', style: TextStyle(color: accentColor)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: accentColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: user == null
            ? const Center(
                child: Text('No user found', style: TextStyle(color: accentColor)),
              )
            : FutureBuilder<String?>(
                future: _fetchName(user.uid),
                builder: (context, snapshot) {
                  final name = snapshot.data ?? user.displayName ?? '';
                  final email = user.email ?? '';
                  final joined = _formatDate(user.metadata.creationTime);
                  final phone = user.phoneNumber;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      children: [
                        // Header card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [secondaryColor.withOpacity(0.9), secondaryColor],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: highlightColor,
                                backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                                child: user.photoURL == null
                                    ? Text(
                                        _initialsFrom(name, email),
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 20,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isNotEmpty ? name : 'User',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: accentColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Info card
                        Card(
                          color: secondaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.badge, color: accentColor),
                                  title: const Text('Display name', style: TextStyle(color: accentColor)),
                                  subtitle: Text(
                                    name.isNotEmpty ? name : 'Not set',
                                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                  ),
                                ),
                                const Divider(height: 1, color: Colors.white24),
                                ListTile(
                                  leading: const Icon(Icons.email, color: accentColor),
                                  title: const Text('Email', style: TextStyle(color: accentColor)),
                                  subtitle: Text(
                                    email.isNotEmpty ? email : 'Not set',
                                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                  ),
                                ),
                                if (phone != null) ...[
                                  const Divider(height: 1, color: Colors.white24),
                                  ListTile(
                                    leading: const Icon(Icons.phone, color: accentColor),
                                    title: const Text('Phone', style: TextStyle(color: accentColor)),
                                    subtitle: Text(
                                      phone,
                                      style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                    ),
                                  ),
                                ],
                                const Divider(height: 1, color: Colors.white24),
                                ListTile(
                                  leading: const Icon(Icons.calendar_today, color: accentColor),
                                  title: const Text('Joined', style: TextStyle(color: accentColor)),
                                  subtitle: Text(
                                    joined,
                                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Actions card (placeholders for future)
                        Card(
                          color: secondaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.lock, color: accentColor),
                                  title: const Text('Security', style: TextStyle(color: accentColor)),
                                  subtitle: Text(
                                    'Manage sign-in & security settings',
                                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                  ),
                                  onTap: () {},
                                ),
                                const Divider(height: 1, color: Colors.white24),
                                ListTile(
                                  leading: const Icon(Icons.settings, color: accentColor),
                                  title: const Text('App settings', style: TextStyle(color: accentColor)),
                                  subtitle: Text(
                                    'Preferences and personalization',
                                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                  ),
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}