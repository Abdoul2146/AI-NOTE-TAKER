import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // To get the current user's ID
import 'package:cloud_firestore/cloud_firestore.dart'; // To interact with Firestore
import 'package:scribesync/models/note_model.dart'; // Import the Note model
// import 'package:scribesync/screens/academyPlanner.dart';
// import 'package:scribesync/screens/settings.dart';
import 'package:scribesync/screens/takeNote.dart';
import 'package:scribesync/screens/note_detail_screen.dart'; // Import the NoteDetailScreen
import 'package:scribesync/screens/profilePage.dart'; // Import the ProfileScreen
// import 'package:scribesync/screens/recordings_screen.dart';

// Your color constants
const Color primaryColor = Color(0xFF1E3F1F);
const Color secondaryColor = Color(0xFF2E6531);
const Color accentColor = Colors.white;
const Color highlightColor = Color(0xFF50AF53);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
//  class _NoteDisplay {
//     final Note note;
//     final bool isFromRecording;
//     _NoteDisplay(this.note, this.isFromRecording);
//   }

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = _auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            child: const CircleAvatar(
              backgroundColor: secondaryColor,
              child: Icon(Icons.person, color: accentColor),
            ),
          ),
        ),
        title:
            _isSearching
                ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: accentColor),
                  decoration: const InputDecoration(
                    hintText: 'Search notes...',
                    hintStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                    });
                  },
                )
                : const Text('Notes', style: TextStyle(color: accentColor)),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: accentColor,
            ),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
        ],
      ),
      body:
          userId == null
              ? const Center(
                child: Text(
                  'Not signed in',
                  style: TextStyle(color: accentColor),
                ),
              )
              : StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance
                        .collection(
                          'notes',
                        ) // <-- Changed from 'recordings' to 'notes'
                        .where('userId', isEqualTo: userId)
                        // .orderBy('timestamp', descending: true)
                        .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snap.error}',
                        style: const TextStyle(color: accentColor),
                      ),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: accentColor),
                    );
                  }

                  final docs = snap.data?.docs ?? [];

                  // Build notes from Firestore
                  final List<Note> items =
                      docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        dynamic ts = data['timestamp'];
                        Timestamp timestamp;
                        if (ts is Timestamp) {
                          timestamp = ts;
                        } else if (ts is String) {
                          // Try to parse ISO8601 string
                          try {
                            timestamp = Timestamp.fromDate(DateTime.parse(ts));
                          } catch (_) {
                            timestamp = Timestamp.now();
                          }
                        } else {
                          timestamp = Timestamp.now();
                        }
                        return Note(
                          id: doc.id,
                          title: (data['title'] ?? 'Note').toString(),
                          content: (data['content'] ?? '').toString(),
                          language: (data['language'] ?? 'English').toString(),
                          subject: (data['subject'] ?? 'General').toString(),
                          timestamp: timestamp,
                        );
                      }).toList();

                  // Search filter
                  final filtered =
                      _searchQuery.isEmpty
                          ? items
                          : items.where((n) {
                            final t = n.title.toLowerCase();
                            final c = n.content.toLowerCase();
                            return t.contains(_searchQuery) ||
                                c.contains(_searchQuery);
                          }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off
                                : Icons.note_add,
                            size: 64,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No notes found for "$_searchQuery"'
                                : 'No notes yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Try a different search term'
                                : 'Create a note to see it here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final note = filtered[index];
                      return _buildNoteCard(note, isFromRecording: false);
                    },
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const TakeNoteScreen()),
          );
        },
        backgroundColor: highlightColor,
        foregroundColor: primaryColor,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildNoteCard(Note note, {bool isFromRecording = false}) {
    return Card(
      color: secondaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        title: Text(
          note.title,
          style: const TextStyle(
            color: accentColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          note.content.length > 50
              ? '${note.content.substring(0, 50)}...'
              : note.content,
          style: const TextStyle(color: Colors.white70),
        ),
        trailing:
            isFromRecording
                ? null
                : IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () async {
                    final user = _auth.currentUser;
                    if (user != null && (note.id?.isNotEmpty ?? false)) {
                      await FirebaseFirestore.instance
                          .collection('notes')
                          .doc(note.id)
                          .delete();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Note deleted'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) => NoteDetailScreen(
                    note: note,
                    isFromRecording: isFromRecording,
                  ),
            ),
          );
        },
      ),
    );
  }
}
