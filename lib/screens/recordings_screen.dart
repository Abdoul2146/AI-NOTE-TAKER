import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scribesync/models/recording_model.dart';
import 'package:scribesync/screens/takeNote.dart';
import 'package:intl/intl.dart';

const Color primaryColor = Color(0xFF1E3F1F);
const Color secondaryColor = Color(0xFF2E6531);
const Color accentColor = Colors.white;
const Color highlightColor = Color(0xFF50AF53);

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Recording> _recordings = [];

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final querySnapshot =
          await _firestore
              .collection('recordings')
              .where('userId', isEqualTo: user.uid)
              .orderBy('timestamp', descending: true)
              .get();

      final recordings = <Recording>[];

      for (var doc in querySnapshot.docs) {
        final recording = Recording.fromFirestore(doc);
        // Check if file still exists locally
        if (await recording.fileExists()) {
          recordings.add(recording);
        } else {
          // Remove from Firestore if file doesn't exist locally
          await doc.reference.delete();
        }
      }

      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading recordings: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecording(Recording recording) async {
    try {
      // Delete local file
      final file = File(recording.filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // Delete from Firestore
      if (recording.id != null) {
        await _firestore.collection('recordings').doc(recording.id).delete();
      }

      // Reload recordings
      await _loadRecordings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording deleted successfully')),
        );
      }
    } catch (e) {
      print('Error deleting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error deleting recording')),
        );
      }
    }
  }

  void _openRecording(Recording recording) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TakeNoteScreen(recording: recording),
      ),
    ).then((_) => _loadRecordings()); // Reload after returning
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: const Text('Recordings', style: TextStyle(color: accentColor)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: accentColor),
            onPressed: _loadRecordings,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: accentColor),
              )
              : _recordings.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mic_off,
                      size: 64,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No recordings yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create recordings to see them here',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _recordings.length,
                itemBuilder: (context, index) {
                  final recording = _recordings[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: secondaryColor,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: highlightColor,
                        child: Icon(Icons.mic, color: accentColor),
                      ),
                      title: Text(
                        recording.title,
                        style: const TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'MMM dd, yyyy - HH:mm',
                            ).format(recording.timestamp),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                recording.formattedDuration,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.description,
                                size: 12,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              const SizedBox(width: 4),
                              FutureBuilder<String>(
                                future: recording.formattedFileSize,
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? '...',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          if (recording.transcription != null &&
                              recording.transcription!.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                recording.transcription!,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: accentColor),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _deleteRecording(recording);
                          }
                        },
                        itemBuilder:
                            (context) => [
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                      ),
                      onTap: () => _openRecording(recording),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TakeNoteScreen()),
          );
        },
        backgroundColor: highlightColor,
        foregroundColor: primaryColor,
        child: const Icon(Icons.add),
      ),
    );
  }
}
