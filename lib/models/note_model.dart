import 'package:cloud_firestore/cloud_firestore.dart';

class Note {
  final String? id;
  final String title;
  final String content;
  final String? language;
  final String? subject;
  final Timestamp timestamp;

  Note({
    this.id,
    required this.title,
    required this.content,
    this.language,
    this.subject,
    required this.timestamp,
  });

  // Factory constructor to create a Note from a Firestore document
  factory Note.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Note(
      id: doc.id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      language: data['language'] ?? 'English',
      subject: data['subject'] ?? 'General',
      timestamp: data['timestamp'] ?? Timestamp.now(),
    );
  }

  // Method to convert the Note object to a Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'content': content,
      'language': language,
      'subject': subject,
      'timestamp': timestamp,
    };
  }
}

class Task {
  final String id;
  final String title;
  final String dueDate; // Store as ISO string or timestamp
  final String status;
  final Timestamp timestamp;

  Task({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.status,
    required this.timestamp,
  });

  factory Task.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      title: data['title'] ?? '',
      dueDate: data['dueDate'] ?? '',
      status: data['status'] ?? 'To-Do',
      timestamp: data['timestamp'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'dueDate': dueDate,
      'status': status,
      'timestamp': timestamp,
    };
  }
}
