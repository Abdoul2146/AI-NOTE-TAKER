import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:scribesync/screens/settings.dart';
// import 'package:scribesync/screens/homeScreen.dart';
import 'package:scribesync/models/note_model.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart'; // Importing intl for date formatting
import 'package:flutter_timezone/flutter_timezone.dart';


// Using the same color scheme for consistency
const Color primaryColor = Color(0xFF1E3F1F); // Dark green background
const Color secondaryColor = Color(0xFF2E6531); // Darker green UI elements
const Color accentColor = Colors.white; // White text and UI elements
const Color highlightColor = Color(0xFF50AF53); // Lighter green for highlights

class AcademicPlannerScreen extends StatefulWidget {
  const AcademicPlannerScreen({super.key});

  @override
  State<AcademicPlannerScreen> createState() => _AcademicPlannerScreenState();
}

class _AcademicPlannerScreenState extends State<AcademicPlannerScreen> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  DateTime _focusedMonth = DateTime.now();
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

Future<void> _initializeNotifications() async {
  tz.initializeTimeZones();
  final currentTimeZone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(currentTimeZone));

  final android = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  await android?.requestNotificationsPermission();
  await android?.requestExactAlarmsPermission();

  const channel = AndroidNotificationChannel(
    'your_channel_id',
    'Reminders',
    description: 'Notifications for academic reminders with custom sound.',
    importance: Importance.high,
    playSound: true,
  );
  await android?.createNotificationChannel(channel);

  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initAndroid),
    onDidReceiveNotificationResponse: (resp) {
      // handle tap
    },
  );
}
  Future<void> _scheduleNotification(
    String title,
    DateTime dueDate,
    String taskId,
  ) async {
    // Calculate the time for the notification (10 minutes before the due date)
    final scheduledTime = dueDate.subtract(const Duration(minutes: 10));

    // --- Start of Debugging Prints ---
    print('--- Notification Debugging ---');
    print('Task Title: $title');
    print('Original Due Date: $dueDate');
    print('Calculated Scheduled Time: $scheduledTime');
    print('Current Time: ${DateTime.now()}');
    // --- End of Debugging Prints ---

    if (scheduledTime.isAfter(DateTime.now())) {
      print('Status: Scheduled time is in the future. Proceeding to schedule.');
   await flutterLocalNotificationsPlugin.zonedSchedule(
  taskId.hashCode,
  'Upcoming Deadline',
  'Your task "$title" is due soon!',
  tz.TZDateTime.from(scheduledTime, tz.local),
  const NotificationDetails(
    android: AndroidNotificationDetails(
      'your_channel_id',
      'Reminders',
      channelDescription: 'Reminders for academic tasks',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      category: AndroidNotificationCategory.alarm,
      icon: '@mipmap/ic_launcher',
    ),
  ),
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
  // remove matchDateTimeComponents for one-off
);
      print('Result: Notification successfully scheduled.');
    } else {
      print(
        'Status: Scheduled time is in the past. Notification was NOT scheduled.',
      );
    }
    print('----------------------------');
  }

  Future<void> _addTask(String title, DateTime dueDate) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .add({
          'title': title,
          'dueDate': dueDate.toIso8601String(),
          'status': 'To-Do',
          'timestamp': Timestamp.fromDate(dueDate),
        });
    // Pass the new task's document ID to the notification scheduler
    await _scheduleNotification(title, dueDate, docRef.id);
  }

  Future<void> _cancelNotification(String taskId) async {
    await flutterLocalNotificationsPlugin.cancel(taskId.hashCode);
  }

  Future<void> _deleteTask(String taskId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .doc(taskId)
        .delete();
    // Cancel the associated notification
    await _cancelNotification(taskId);
  }

  Future<void> _updateTaskStatus(String taskId, String status) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .doc(taskId)
        .update({'status': status});
  }

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    TimeOfDay? selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Task'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Task Title'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (pickedDate != null) {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (pickedTime != null) {
                        selectedDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                        );
                        selectedTime = pickedTime;
                      }
                    }
                  },
                  child: const Text('Pick Due Date and Time'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (titleController.text.isNotEmpty &&
                      selectedDate != null &&
                      selectedTime != null) {
                    final dueDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedTime!.hour,
                      selectedTime!.minute,
                    );
                    _addTask(titleController.text, dueDateTime);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  // Add this helper method in your class:
  String _formatDateTime(String isoString) {
    final dateTime = DateTime.parse(isoString);
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime); // 24-hour format
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: const Text(
          'Academic Planner',
          style: TextStyle(color: accentColor),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              children: [
                _buildCalendarHeader(),
                const SizedBox(height: 8),
                _buildCalendarGrid(),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser!.uid)
                          .collection('tasks')
                          .orderBy('timestamp')
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var tasks =
                        snapshot.data!.docs
                            .map((doc) => Task.fromFirestore(doc))
                            .toList();

                    // Filter by selected day if any
                    if (_selectedDay != null) {
                      final selectedDate = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month,
                        _selectedDay!,
                      );
                      tasks =
                          tasks.where((task) {
                            final taskDate = DateTime.parse(task.dueDate);
                            return taskDate.year == selectedDate.year &&
                                taskDate.month == selectedDate.month &&
                                taskDate.day == selectedDate.day;
                          }).toList();
                    }

                    if (tasks.isEmpty) {
                      return const Text('No tasks for this day.');
                    }

                    // Group tasks by date
                    Map<DateTime, List<Task>> tasksByDate = {};
                    for (var task in tasks) {
                      final taskDate = DateTime.parse(task.dueDate);
                      final day = DateTime(
                        taskDate.year,
                        taskDate.month,
                        taskDate.day,
                      );
                      tasksByDate.putIfAbsent(day, () => []).add(task);
                    }

                    return Column(
                      children:
                          tasksByDate.keys.map((date) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                  ),
                                  child: Text(
                                    '${_monthName(date.month)} ${date.day}, ${date.year}',
                                    style: const TextStyle(
                                      color: highlightColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ...tasksByDate[date]!
                                    .map(
                                      (task) => _buildTaskItem(
                                        task.title,
                                        task.dueDate,
                                        task.status,
                                        Icons.book_outlined,
                                        onDelete: () => _deleteTask(task.id),
                                        onStatusChange:
                                            (newStatus) => _updateTaskStatus(
                                              task.id,
                                              newStatus,
                                            ),
                                      ),
                                    )
                                    .toList(),
                              ],
                            );
                          }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Implement action for adding a new task
          _showAddTaskDialog();
        },
        backgroundColor: secondaryColor,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: accentColor),
      ),
    );
  }

  Widget _buildCalendarHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: accentColor, size: 20),
          onPressed: () {
            setState(() {
              _focusedMonth = DateTime(
                _focusedMonth.year,
                _focusedMonth.month - 1,
              );
              _selectedDay = null; // Clear day selection on month change
            });
          },
        ),
        Text(
          "${_monthName(_focusedMonth.month)} ${_focusedMonth.year}",
          style: const TextStyle(
            color: accentColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.arrow_forward_ios,
            color: accentColor,
            size: 20,
          ),
          onPressed: () {
            setState(() {
              _focusedMonth = DateTime(
                _focusedMonth.year,
                _focusedMonth.month + 1,
              );
              _selectedDay = null; // Clear day selection on month change
            });
          },
        ),
      ],
    );
  }

  // Helper to get month name
  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  Widget _buildCalendarGrid() {
    const List<String> daysOfWeek = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final firstDayOfMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      1,
    );
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final startDay =
        firstDayOfMonth.weekday % 7; // Sunday=0, Monday=1, ..., Saturday=6

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children:
              daysOfWeek
                  .map(
                    (day) =>
                        Text(day, style: const TextStyle(color: Colors.grey)),
                  )
                  .toList(),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.0,
          ),
          itemCount: daysInMonth + startDay,
          itemBuilder: (context, index) {
            if (index < startDay) {
              return const SizedBox.shrink();
            }
            final day = index - startDay + 1;
            final isSelected = _selectedDay == day;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDay = day;
                });
              },
              child: Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.all(4),
                decoration:
                    isSelected
                        ? BoxDecoration(
                          color: highlightColor,
                          borderRadius: BorderRadius.circular(12),
                        )
                        : null,
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: isSelected ? accentColor : accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTaskItem(
    String title,
    String dueDate,
    String status,
    IconData icon, {
    required VoidCallback onDelete,
    void Function(String)? onStatusChange,
  }) {
    Color statusColor;
    switch (status) {
      case 'Completed':
        statusColor = highlightColor;
        break;
      case 'In Progress':
        statusColor = Colors.yellow;
        break;
      default:
        statusColor = Colors.grey;
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: secondaryColor,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: accentColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(dueDate),
                  style: TextStyle(
                    color: accentColor.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: onDelete,
            tooltip: 'Delete Task',
          ),
        ],
      ),
    );
  }
}
