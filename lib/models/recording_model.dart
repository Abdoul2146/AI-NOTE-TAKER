import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

class Recording {
  final String? id;
  final String title;
  final String filePath;
  final String? transcription;
  final DateTime timestamp;
  final Duration duration;
  final String userId;

  Recording({
    this.id,
    required this.title,
    required this.filePath,
    this.transcription,
    required this.timestamp,
    required this.duration,
    required this.userId,
  });

  // Factory constructor to create a Recording from a Firestore document
  factory Recording.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Recording(
      id: doc.id,
      title: data['title'] ?? '',
      filePath: data['filePath'] ?? '',
      transcription: data['transcription'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      duration: Duration(milliseconds: data['duration'] ?? 0),
      userId: data['userId'] ?? '',
    );
  }

  // Method to convert the Recording object to a Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'filePath': filePath,
      'transcription': transcription,
      'timestamp': Timestamp.fromDate(timestamp),
      'duration': duration.inMilliseconds,
      'userId': userId,
    };
  }

  // Check if the audio file exists locally
  Future<bool> fileExists() async {
    final file = File(filePath);
    return await file.exists();
  }

  // Get file size
  Future<int> getFileSize() async {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  // Format duration for display
  String get formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  // Format file size for display
  Future<String> get formattedFileSize async {
    final size = await getFileSize();
    if (size < 1024) {
      return '${size}B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }
}