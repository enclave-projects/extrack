import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:math' as math;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service which will also set up timezone
  await NotificationService.init();

  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// Notification Service
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // Initialize timezone information first
    await _initializeTimeZone();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        // Handle notification tap
        print("Notification tapped: ${response.payload}");
      },
    );

    // Handle permissions on Android
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      // Request notification permission
      final bool? areNotificationsEnabled = await androidImplementation
          ?.areNotificationsEnabled();

      if (areNotificationsEnabled == false) {
        print(
          "Notifications not enabled, but we won't request permission programmatically as it varies by Android version",
        );
        // Permission will be requested by the system when a notification is shown
      }

      // Request exact alarm permission (for scheduled notifications)
      await requestExactAlarmPermission();
    }
  }

  // Initialize timezone information
  static Future<void> _initializeTimeZone() async {
    try {
      // Initialize timezone database
      tz.initializeTimeZones();

      // Set to Asia/Kolkata timezone
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

      print("Timezone initialized to Asia/Kolkata successfully");
    } catch (e) {
      print("Error initializing timezone: $e");
      // Fallback to UTC if there's an error
      try {
        tz.setLocalLocation(tz.UTC);
        print("Timezone fallback to UTC");
      } catch (e) {
        print("Error setting UTC timezone: $e");
      }
    }
  }

  // Function to request exact alarm permission on Android
  static Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;

    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      if (androidImplementation != null) {
        await androidImplementation.requestExactAlarmsPermission();
        print("Requested exact alarms permission");
      }
    } catch (e) {
      print("Error requesting exact alarms permission: $e");
    }
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    try {
      print(
        'Scheduling notification for: ${scheduledDate.toString()}, ID: $id',
      );

      // Calculate proper time zone aware DateTime
      final tz.TZDateTime scheduledTZDateTime = _nextInstanceOfTime(
        scheduledDate,
      );

      print('TZ scheduled time: ${scheduledTZDateTime.toString()}');

      // For immediate notifications (within 10 seconds), use show() instead of zonedSchedule
      if (scheduledDate.difference(DateTime.now()).inSeconds < 10) {
        await _notifications.show(
          id,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'expense_reminder',
              'Expense Reminders',
              channelDescription: 'Notifications for expense reminders',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
              fullScreenIntent: true,
              visibility: NotificationVisibility.public,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
        );
        print('Immediate notification shown with ID: $id');
        return;
      }

      // For scheduled notifications, try to use exact alarms if available
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduledTZDateTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'expense_reminder',
            'Expense Reminders',
            channelDescription: 'Notifications for expense reminders',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      print('Notification scheduled successfully with ID: $id');
    } catch (e) {
      print('Error scheduling notification with exact alarm: $e');

      // Fallback to inexact scheduling if exact alarms not permitted
      try {
        final tz.TZDateTime scheduledTZDateTime = _nextInstanceOfTime(
          scheduledDate,
        );

        await _notifications.zonedSchedule(
          id,
          title,
          body,
          scheduledTZDateTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'expense_reminder',
              'Expense Reminders',
              channelDescription: 'Notifications for expense reminders',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        print('Notification scheduled with inexact alarm, ID: $id');
      } catch (e) {
        print('Failed to schedule notification entirely: $e');
      }
    }
  }

  // Helper method to ensure proper timezone handling
  static tz.TZDateTime _nextInstanceOfTime(DateTime scheduledDate) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledTZDateTime = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    );

    // If the scheduled time is in the past, reschedule intelligently
    if (scheduledTZDateTime.isBefore(now)) {
      print('Scheduled time is in the past, adjusting to future');

      // If it's the same day, add one day
      if (scheduledTZDateTime.day == now.day &&
          scheduledTZDateTime.month == now.month &&
          scheduledTZDateTime.year == now.year) {
        scheduledTZDateTime = scheduledTZDateTime.add(const Duration(days: 1));
      } else {
        // Otherwise, keep the time but change to today or tomorrow
        final newDateTime = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          scheduledDate.hour,
          scheduledDate.minute,
        );

        // If the new time is still in the past (earlier today), push to tomorrow
        if (newDateTime.isBefore(now)) {
          scheduledTZDateTime = newDateTime.add(const Duration(days: 1));
        } else {
          scheduledTZDateTime = newDateTime;
        }
      }

      print('Adjusted to: ${scheduledTZDateTime.toString()}');
    }

    return scheduledTZDateTime;
  }

  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  static Future<void> showTestNotification() async {
    try {
      final int id = DateTime.now().millisecondsSinceEpoch % 100000;

      await _notifications.show(
        id,
        'Test Notification',
        'This is a test notification to verify that notifications are working properly',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'test_channel',
            'Test Notifications',
            channelDescription: 'For testing notifications',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );

      print('Test notification shown with ID: $id');
    } catch (e) {
      print('Error showing test notification: $e');
    }
  }
}

// Models
class Transaction {
  final String id;
  final double amount;
  final String category;
  final DateTime date;
  final String? notes;
  final TransactionType type;

  Transaction({
    required this.id,
    required this.amount,
    required this.category,
    required this.date,
    this.notes,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'category': category,
    'date': date.toIso8601String(),
    'notes': notes,
    'type': type.toString(),
  };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: json['id'],
    amount: json['amount'].toDouble(),
    category: json['category'],
    date: DateTime.parse(json['date']),
    notes: json['notes'],
    type: json['type'] == 'TransactionType.income'
        ? TransactionType.income
        : TransactionType.expense,
  );
}

enum TransactionType { income, expense }

class Category {
  final String name;
  final IconData icon;
  final Color color;

  Category({required this.name, required this.icon, required this.color});
}

// Reminder Model
class Reminder {
  final String id;
  final String title;
  final String description;
  final DateTime dateTime;
  final ReminderType type;
  final bool isActive;
  final double? amount;

  Reminder({
    required this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    required this.type,
    this.isActive = true,
    this.amount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'dateTime': dateTime.toIso8601String(),
    'type': type.toString(),
    'isActive': isActive,
    'amount': amount,
  };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    dateTime: DateTime.parse(json['dateTime']),
    type: ReminderType.values.firstWhere((e) => e.toString() == json['type']),
    isActive: json['isActive'] ?? true,
    amount: json['amount']?.toDouble(),
  );
}

enum ReminderType {
  billPayment,
  salaryReminder,
  budgetReview,
  subscription,
  savingsGoal,
  taxPayment,
  custom,
}

// Data Manager
class DataManager {
  static const String _transactionsKey = 'transactions';
  static const String _categoriesKey = 'categories';
  static const String _currencyKey = 'currency';
  static const String _themeKey = 'theme';
  static const String _remindersKey = 'reminders';

  static Future<List<Transaction>> getTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? transactionsJson = prefs.getString(_transactionsKey);
    if (transactionsJson == null) return [];

    final List<dynamic> decoded = json.decode(transactionsJson);
    return decoded.map((item) => Transaction.fromJson(item)).toList();
  }

  static Future<void> saveTransactions(List<Transaction> transactions) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(
      transactions.map((t) => t.toJson()).toList(),
    );
    await prefs.setString(_transactionsKey, encoded);
  }

  static Future<List<Reminder>> getReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? remindersJson = prefs.getString(_remindersKey);
    if (remindersJson == null) return [];

    final List<dynamic> decoded = json.decode(remindersJson);
    return decoded.map((item) => Reminder.fromJson(item)).toList();
  }

  static Future<void> saveReminders(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(
      reminders.map((r) => r.toJson()).toList(),
    );
    await prefs.setString(_remindersKey, encoded);
  }

  static Future<String> getCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currencyKey) ?? '\$';
  }

  static Future<void> setCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, currency);
  }
}

// Main Screen with Navigation
class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Transaction> _transactions = [];
  List<Reminder> _reminders = [];
  String _currency = '\$';
  String _searchQuery = '';

  final List<Category> _defaultCategories = [
    Category(name: 'Salary', icon: Icons.attach_money, color: Colors.green),
    Category(name: 'Food', icon: Icons.restaurant, color: Colors.orange),
    Category(name: 'Transport', icon: Icons.directions_car, color: Colors.blue),
    Category(name: 'Shopping', icon: Icons.shopping_bag, color: Colors.purple),
    Category(name: 'Entertainment', icon: Icons.movie, color: Colors.red),
    Category(name: 'Bills', icon: Icons.receipt, color: Colors.brown),
    Category(
      name: 'Healthcare',
      icon: Icons.local_hospital,
      color: Colors.pink,
    ),
    Category(name: 'Education', icon: Icons.school, color: Colors.indigo),
    Category(name: 'Other', icon: Icons.category, color: Colors.grey),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final transactions = await DataManager.getTransactions();
    final reminders = await DataManager.getReminders();
    final currency = await DataManager.getCurrency();
    setState(() {
      _transactions = transactions;
      _reminders = reminders;
      _currency = currency;
    });

    // Reschedule active reminders when app starts
    _rescheduleReminders();
  }

  void _addTransaction(Transaction transaction) async {
    setState(() {
      _transactions.add(transaction);
    });
    await DataManager.saveTransactions(_transactions);
  }

  void _updateTransaction(String id, Transaction newTransaction) async {
    setState(() {
      final index = _transactions.indexWhere((t) => t.id == id);
      if (index != -1) {
        _transactions[index] = newTransaction;
      }
    });
    await DataManager.saveTransactions(_transactions);
  }

  void _deleteTransaction(String id) async {
    setState(() {
      _transactions.removeWhere((t) => t.id == id);
    });
    await DataManager.saveTransactions(_transactions);
  }

  void _addReminder(Reminder reminder) async {
    setState(() {
      _reminders.add(reminder);
    });
    await DataManager.saveReminders(_reminders);

    // Schedule notification
    await NotificationService.scheduleNotification(
      id: reminder.id.hashCode,
      title: reminder.title,
      body: reminder.description,
      scheduledDate: reminder.dateTime,
    );
  }

  void _updateReminder(String id, Reminder newReminder) async {
    setState(() {
      final index = _reminders.indexWhere((r) => r.id == id);
      if (index != -1) {
        _reminders[index] = newReminder;
      }
    });
    await DataManager.saveReminders(_reminders);

    // Cancel old notification and schedule new one
    await NotificationService.cancelNotification(id.hashCode);
    if (newReminder.isActive) {
      await NotificationService.scheduleNotification(
        id: newReminder.id.hashCode,
        title: newReminder.title,
        body: newReminder.description,
        scheduledDate: newReminder.dateTime,
      );
    }
  }

  void _deleteReminder(String id) async {
    setState(() {
      _reminders.removeWhere((r) => r.id == id);
    });
    await DataManager.saveReminders(_reminders);
    await NotificationService.cancelNotification(id.hashCode);
  }

  // Reschedule all active reminders
  Future<void> _rescheduleReminders() async {
    print('Rescheduling ${_reminders.length} reminders');

    // Cancel all existing notifications first
    await NotificationService.cancelAllNotifications();

    // Add a slight delay before rescheduling to avoid conflicts
    await Future.delayed(const Duration(milliseconds: 500));

    // Request exact alarm permission if on Android
    if (Platform.isAndroid) {
      await NotificationService.requestExactAlarmPermission();
    }

    // Reschedule active reminders
    int scheduledCount = 0;
    for (final reminder in _reminders) {
      if (reminder.isActive) {
        print(
          'Rescheduling reminder: ${reminder.title} for ${reminder.dateTime}',
        );

        try {
          await NotificationService.scheduleNotification(
            id: reminder.id.hashCode,
            title: reminder.title,
            body: reminder.description,
            scheduledDate: reminder.dateTime,
          );
          scheduledCount++;
        } catch (e) {
          print('Failed to reschedule reminder: ${reminder.title}, error: $e');
        }
      }
    }

    print('Successfully rescheduled $scheduledCount reminders');

    // Schedule a test notification for 10 seconds from now to verify permissions
    if (scheduledCount == 0 && _reminders.isNotEmpty) {
      print('Scheduling a test notification to verify permissions');
      try {
        await NotificationService.scheduleNotification(
          id: 999999,
          title: 'Test Notification',
          body: 'This is a test to verify notification permissions',
          scheduledDate: DateTime.now().add(const Duration(seconds: 10)),
        );
      } catch (e) {
        print('Failed to schedule test notification: $e');
      }
    }
  }

  double get _totalIncome => _transactions
      .where((t) => t.type == TransactionType.income)
      .fold(0, (sum, t) => sum + t.amount);

  double get _totalExpense => _transactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0, (sum, t) => sum + t.amount);

  double get _balance => _totalIncome - _totalExpense;

  List<Transaction> get _filteredTransactions {
    if (_searchQuery.isEmpty) return _transactions;
    return _transactions.where((t) {
      return t.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (t.notes?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          t.amount.toString().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildDashboard(),
      _buildTransactionsList(),
      _buildReminders(),
      _buildCategories(),
      _buildSettings(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(icon: Icon(Icons.list), label: 'Transactions'),
          NavigationDestination(
            icon: Icon(Icons.notifications),
            label: 'Remember',
          ),
          NavigationDestination(
            icon: Icon(Icons.category),
            label: 'Categories',
          ),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
          ? FloatingActionButton(
              onPressed: () => _showAddTransactionDialog(),
              child: const Icon(Icons.add),
            )
          : _selectedIndex == 2
          ? FloatingActionButton(
              onPressed: () => _showAddReminderDialog(),
              child: const Icon(Icons.add_alert),
            )
          : null,
    );
  }

  Widget _buildDashboard() {
    final recentTransactions = _transactions.reversed.take(5).toList();
    final upcomingReminders =
        _reminders
            .where((r) => r.isActive && r.dateTime.isAfter(DateTime.now()))
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Total Balance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_currency${_balance.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: _balance >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Income and Expense Cards
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.green.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.arrow_downward, color: Colors.green),
                          const SizedBox(height: 8),
                          Text(
                            'Income',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_currency${_totalIncome.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    color: Colors.red.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.arrow_upward, color: Colors.red),
                          const SizedBox(height: 8),
                          Text(
                            'Expenses',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_currency${_totalExpense.toStringAsFixed(2)}',
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Upcoming Reminders Section
            if (upcomingReminders.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Upcoming Reminders',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...upcomingReminders
                  .take(3)
                  .map(
                    (reminder) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          _getReminderIcon(reminder.type),
                          color: _getReminderColor(reminder.type),
                        ),
                        title: Text(reminder.title),
                        subtitle: Text(
                          DateFormat(
                            'MMM dd, yyyy - hh:mm a',
                          ).format(reminder.dateTime),
                        ),
                        trailing: reminder.amount != null
                            ? Text(
                                '$_currency${reminder.amount!.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              )
                            : null,
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 24),
            // Recent Transactions
            Text(
              'Recent Transactions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (recentTransactions.isEmpty)
              Center(
                child: Text(
                  'No transactions yet',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            else
              ...recentTransactions.map(
                (transaction) => _buildTransactionTile(transaction),
              ),
            const SizedBox(height: 16),
            // Category Breakdown
            Text(
              'Category Breakdown',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildCategoryBreakdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    Map<String, double> categoryTotals = {};
    for (var transaction in _transactions) {
      if (transaction.type == TransactionType.expense) {
        categoryTotals[transaction.category] =
            (categoryTotals[transaction.category] ?? 0) + transaction.amount;
      }
    }

    if (categoryTotals.isEmpty) {
      return Center(
        child: Text(
          'No expenses to analyze',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sortedCategories.map((entry) {
        final percentage = (entry.value / _totalExpense * 100);
        final category = _defaultCategories.firstWhere(
          (c) => c.name == entry.key,
          orElse: () => Category(
            name: entry.key,
            icon: Icons.category,
            color: Colors.grey,
          ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(category.icon, color: category.color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key),
                        Text('$_currency${entry.value.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation(category.color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${percentage.toStringAsFixed(1)}%'),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTransactionsList() {
    final sortedTransactions = List<Transaction>.from(_filteredTransactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                filled: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ),
      ),
      body: sortedTransactions.isEmpty
          ? Center(
              child: Text(
                _searchQuery.isEmpty
                    ? 'No transactions yet'
                    : 'No transactions found',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: sortedTransactions.length,
              itemBuilder: (context, index) {
                return _buildTransactionTile(sortedTransactions[index]);
              },
            ),
    );
  }

  Widget _buildTransactionTile(Transaction transaction) {
    final category = _defaultCategories.firstWhere(
      (c) => c.name == transaction.category,
      orElse: () => Category(
        name: transaction.category,
        icon: Icons.category,
        color: Colors.grey,
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: category.color.withOpacity(0.2),
          child: Icon(category.icon, color: category.color),
        ),
        title: Text(transaction.category),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM dd, yyyy - hh:mm a').format(transaction.date)),
            if (transaction.notes != null && transaction.notes!.isNotEmpty)
              Text(
                transaction.notes!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Text(
          '${transaction.type == TransactionType.income ? '+' : '-'}$_currency${transaction.amount.toStringAsFixed(2)}',
          style: TextStyle(
            color: transaction.type == TransactionType.income
                ? Colors.green
                : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        onTap: () => _showTransactionDetails(transaction),
      ),
    );
  }

  Widget _buildReminders() {
    final activeReminders = _reminders.where((r) => r.isActive).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final pastReminders = _reminders.where((r) => !r.isActive).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return Scaffold(
      appBar: AppBar(title: const Text('Remember'), elevation: 0),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Active', icon: Icon(Icons.alarm_on)),
                Tab(text: 'Past', icon: Icon(Icons.history)),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Active Reminders
                  activeReminders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_off,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No active reminders',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap + to add a reminder',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: activeReminders.length,
                          itemBuilder: (context, index) {
                            return _buildReminderTile(activeReminders[index]);
                          },
                        ),
                  // Past Reminders
                  pastReminders.isEmpty
                      ? Center(
                          child: Text(
                            'No past reminders',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: pastReminders.length,
                          itemBuilder: (context, index) {
                            return _buildReminderTile(pastReminders[index]);
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderTile(Reminder reminder) {
    final isPast = reminder.dateTime.isBefore(DateTime.now());
    final icon = _getReminderIcon(reminder.type);
    final color = _getReminderColor(reminder.type);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          reminder.title,
          style: TextStyle(
            decoration: isPast ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reminder.description),
            Text(
              DateFormat('MMM dd, yyyy - hh:mm a').format(reminder.dateTime),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (reminder.amount != null)
              Text(
                '$_currency${reminder.amount!.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            if (!isPast)
              Text(
                _getTimeRemaining(reminder.dateTime),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        onTap: () => _showReminderDetails(reminder),
      ),
    );
  }

  IconData _getReminderIcon(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return Icons.receipt_long;
      case ReminderType.salaryReminder:
        return Icons.attach_money;
      case ReminderType.budgetReview:
        return Icons.analytics;
      case ReminderType.subscription:
        return Icons.subscriptions;
      case ReminderType.savingsGoal:
        return Icons.savings;
      case ReminderType.taxPayment:
        return Icons.account_balance;
      case ReminderType.custom:
        return Icons.notifications;
    }
  }

  Color _getReminderColor(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return Colors.orange;
      case ReminderType.salaryReminder:
        return Colors.green;
      case ReminderType.budgetReview:
        return Colors.blue;
      case ReminderType.subscription:
        return Colors.purple;
      case ReminderType.savingsGoal:
        return Colors.teal;
      case ReminderType.taxPayment:
        return Colors.red;
      case ReminderType.custom:
        return Colors.grey;
    }
  }

  String _getTimeRemaining(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);

    if (difference.inDays > 0) {
      return 'in ${difference.inDays} days';
    } else if (difference.inHours > 0) {
      return 'in ${difference.inHours} hours';
    } else if (difference.inMinutes > 0) {
      return 'in ${difference.inMinutes} minutes';
    } else {
      return 'soon';
    }
  }

  Widget _buildCategories() {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories'), elevation: 0),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _defaultCategories.length,
        itemBuilder: (context, index) {
          final category = _defaultCategories[index];
          final transactionCount = _transactions
              .where((t) => t.category == category.name)
              .length;
          final totalAmount = _transactions
              .where((t) => t.category == category.name)
              .fold(0.0, (sum, t) => sum + t.amount);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: category.color.withOpacity(0.2),
                child: Icon(category.icon, color: category.color),
              ),
              title: Text(category.name),
              subtitle: Text('$transactionCount transactions'),
              trailing: Text(
                '$_currency${totalAmount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettings() {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Currency Setting
          Card(
            child: ListTile(
              title: const Text('Currency'),
              subtitle: Text('Current: $_currency'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showCurrencyDialog(),
            ),
          ),

          // Test Notifications Button
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Test Notifications'),
              subtitle: const Text(
                'Send a test notification to verify settings',
              ),
              trailing: const Icon(Icons.notifications_active),
              onTap: () async {
                await NotificationService.showTestNotification();

                // Show confirmation dialog
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Test notification sent'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),

          // Theme setting
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Theme'),
              subtitle: Text(
                Theme.of(context).brightness == Brightness.dark
                    ? 'Dark'
                    : 'Light',
              ),
              trailing: Switch(
                value: Theme.of(context).brightness == Brightness.dark,
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Theme switching requires app restart'),
                    ),
                  );
                },
              ),
            ),
          ),

          // Export Data
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Export Data'),
              subtitle: const Text('Export transactions to CSV'),
              trailing: const Icon(Icons.download),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Export feature coming soon!')),
                );
              },
            ),
          ),

          // Clear Data
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Clear All Data'),
              subtitle: const Text('Delete all transactions and reminders'),
              trailing: const Icon(Icons.delete_forever),
              onTap: () => _confirmClearData(),
            ),
          ),

          // Version Information
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              title: Text('About'),
              subtitle: Text('Version 1.0.0'),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will delete all transactions and reminders permanently. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                _transactions.clear();
                _reminders.clear();
              });
              await DataManager.saveTransactions([]);
              await DataManager.saveReminders([]);
              await NotificationService.cancelAllNotifications();
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('All data cleared')));
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddTransactionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddTransactionSheet(
        categories: _defaultCategories,
        currency: _currency,
        onAdd: _addTransaction,
      ),
    );
  }

  void _showAddReminderDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _AddReminderSheet(currency: _currency, onAdd: _addReminder),
    );
  }

  void _showTransactionDetails(Transaction transaction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(transaction.category),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${transaction.type == TransactionType.income ? 'Income' : 'Expense'}: $_currency${transaction.amount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Date: ${DateFormat('MMMM dd, yyyy - hh:mm a').format(transaction.date)}',
            ),
            if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Notes: ${transaction.notes}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditTransactionDialog(transaction);
            },
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDelete(transaction.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showReminderDetails(Reminder reminder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reminder.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reminder.description),
            const SizedBox(height: 8),
            Text(
              'Date: ${DateFormat('MMMM dd, yyyy - hh:mm a').format(reminder.dateTime)}',
            ),
            if (reminder.amount != null) ...[
              const SizedBox(height: 8),
              Text('Amount: $_currency${reminder.amount!.toStringAsFixed(2)}'),
            ],
            const SizedBox(height: 8),
            Text('Type: ${_getReminderTypeName(reminder.type)}'),
            const SizedBox(height: 8),
            Text('Status: ${reminder.isActive ? "Active" : "Completed"}'),
          ],
        ),
        actions: [
          if (reminder.isActive) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showEditReminderDialog(reminder);
              },
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _toggleReminderStatus(reminder);
              },
              child: const Text('Mark as Done'),
            ),
          ],
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteReminder(reminder.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getReminderTypeName(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return 'Bill Payment';
      case ReminderType.salaryReminder:
        return 'Salary Reminder';
      case ReminderType.budgetReview:
        return 'Budget Review';
      case ReminderType.subscription:
        return 'Subscription';
      case ReminderType.savingsGoal:
        return 'Savings Goal';
      case ReminderType.taxPayment:
        return 'Tax Payment';
      case ReminderType.custom:
        return 'Custom';
    }
  }

  void _toggleReminderStatus(Reminder reminder) {
    final updatedReminder = Reminder(
      id: reminder.id,
      title: reminder.title,
      description: reminder.description,
      dateTime: reminder.dateTime,
      type: reminder.type,
      isActive: false,
      amount: reminder.amount,
    );
    _updateReminder(reminder.id, updatedReminder);
  }

  void _showEditTransactionDialog(Transaction transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddTransactionSheet(
        categories: _defaultCategories,
        currency: _currency,
        onAdd: (newTransaction) {
          _updateTransaction(transaction.id, newTransaction);
        },
        transaction: transaction,
      ),
    );
  }

  void _showEditReminderDialog(Reminder reminder) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddReminderSheet(
        currency: _currency,
        onAdd: (newReminder) {
          _updateReminder(reminder.id, newReminder);
        },
        reminder: reminder,
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text(
          'Are you sure you want to delete this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteTransaction(id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteReminder(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: const Text('Are you sure you want to delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteReminder(id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCurrencyDialog() {
    final currencies = ['\$', '€', '£', '¥', '₹', 'R', 'C\$', 'A\$'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Currency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: currencies
              .map(
                (currency) => ListTile(
                  title: Text(currency),
                  onTap: () async {
                    setState(() {
                      _currency = currency;
                    });
                    await DataManager.setCurrency(currency);
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

// Add Transaction Sheet
class _AddTransactionSheet extends StatefulWidget {
  final List<Category> categories;
  final String currency;
  final Function(Transaction) onAdd;
  final Transaction? transaction;

  const _AddTransactionSheet({
    required this.categories,
    required this.currency,
    required this.onAdd,
    this.transaction,
  });

  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  late TextEditingController _amountController;
  late TextEditingController _notesController;
  late String _selectedCategory;
  late TransactionType _selectedType;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.transaction?.amount.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: widget.transaction?.notes ?? '',
    );
    _selectedCategory =
        widget.transaction?.category ?? widget.categories.first.name;
    _selectedType = widget.transaction?.type ?? TransactionType.expense;
    _selectedDate = widget.transaction?.date ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.transaction == null
                  ? 'Add Transaction'
                  : 'Edit Transaction',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            // Type Selector
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (Set<TransactionType> newSelection) {
                setState(() {
                  _selectedType = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            // Amount Input
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: widget.currency,
                border: const OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
            ),
            const SizedBox(height: 16),
            // Category Dropdown
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: widget.categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.name,
                      child: Row(
                        children: [
                          Icon(category.icon, color: category.color, size: 20),
                          const SizedBox(width: 8),
                          Text(category.name),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            // Date Picker
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(
                DateFormat('MMMM dd, yyyy - hh:mm a').format(_selectedDate),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_selectedDate),
                  );
                  if (time != null) {
                    setState(() {
                      _selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            // Notes Input
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final amount = double.tryParse(_amountController.text);
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid amount'),
                        ),
                      );
                      return;
                    }

                    final transaction = Transaction(
                      id:
                          widget.transaction?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      amount: amount,
                      category: _selectedCategory,
                      date: _selectedDate,
                      notes: _notesController.text.isEmpty
                          ? null
                          : _notesController.text,
                      type: _selectedType,
                    );

                    widget.onAdd(transaction);
                    Navigator.pop(context);
                  },
                  child: Text(widget.transaction == null ? 'Add' : 'Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

// Add Reminder Sheet
class _AddReminderSheet extends StatefulWidget {
  final String currency;
  final Function(Reminder) onAdd;
  final Reminder? reminder;

  const _AddReminderSheet({
    required this.currency,
    required this.onAdd,
    this.reminder,
  });

  @override
  State<_AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<_AddReminderSheet> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _amountController;
  late ReminderType _selectedType;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _includeAmount = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.reminder?.title ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.reminder?.description ?? '',
    );
    _amountController = TextEditingController(
      text: widget.reminder?.amount?.toString() ?? '',
    );
    _selectedType = widget.reminder?.type ?? ReminderType.billPayment;
    _selectedDate = widget.reminder?.dateTime ?? DateTime.now();
    _selectedTime = TimeOfDay.fromDateTime(
      widget.reminder?.dateTime ?? DateTime.now(),
    );
    _includeAmount = widget.reminder?.amount != null;

    // Set default title based on type
    if (widget.reminder == null) {
      _updateDefaultTitle();
    }
  }

  void _updateDefaultTitle() {
    switch (_selectedType) {
      case ReminderType.billPayment:
        _titleController.text = 'Pay Bill';
        break;
      case ReminderType.salaryReminder:
        _titleController.text = 'Salary Day';
        break;
      case ReminderType.budgetReview:
        _titleController.text = 'Review Budget';
        break;
      case ReminderType.subscription:
        _titleController.text = 'Subscription Renewal';
        break;
      case ReminderType.savingsGoal:
        _titleController.text = 'Savings Goal';
        break;
      case ReminderType.taxPayment:
        _titleController.text = 'Tax Payment Due';
        break;
      case ReminderType.custom:
        _titleController.text = '';
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.reminder == null ? 'Add Reminder' : 'Edit Reminder',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              // Type Selector
              DropdownButtonFormField<ReminderType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Reminder Type',
                  border: OutlineInputBorder(),
                ),
                items: ReminderType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_getReminderTypeName(type)),
                      ),
                    )
                    .toList(),
                onChanged: widget.reminder == null
                    ? (value) {
                        setState(() {
                          _selectedType = value!;
                          _updateDefaultTitle();
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              // Title Input
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Description Input
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              // Date and Time Pickers
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(
                        DateFormat('MMM dd, yyyy').format(_selectedDate),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedDate = date;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time'),
                      subtitle: Text(_selectedTime.format(context)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime,
                        );
                        if (time != null) {
                          setState(() {
                            _selectedTime = time;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Amount Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include Amount'),
                value: _includeAmount,
                onChanged: (value) {
                  setState(() {
                    _includeAmount = value;
                  });
                },
              ),
              if (_includeAmount) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: widget.currency,
                    border: const OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_titleController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a title')),
                        );
                        return;
                      }

                      double? amount;
                      if (_includeAmount) {
                        amount = double.tryParse(_amountController.text);
                        if (amount == null || amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid amount'),
                            ),
                          );
                          return;
                        }
                      }

                      final reminderDateTime = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        _selectedTime.hour,
                        _selectedTime.minute,
                      );

                      final reminder = Reminder(
                        id:
                            widget.reminder?.id ??
                            DateTime.now().millisecondsSinceEpoch.toString(),
                        title: _titleController.text,
                        description: _descriptionController.text,
                        dateTime: reminderDateTime,
                        type: _selectedType,
                        isActive: true,
                        amount: amount,
                      );

                      widget.onAdd(reminder);
                      Navigator.pop(context);
                    },
                    child: Text(widget.reminder == null ? 'Add' : 'Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getReminderTypeName(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return 'Bill Payment';
      case ReminderType.salaryReminder:
        return 'Salary Reminder';
      case ReminderType.budgetReview:
        return 'Budget Review';
      case ReminderType.subscription:
        return 'Subscription';
      case ReminderType.savingsGoal:
        return 'Savings Goal';
      case ReminderType.taxPayment:
        return 'Tax Payment';
      case ReminderType.custom:
        return 'Custom';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}
