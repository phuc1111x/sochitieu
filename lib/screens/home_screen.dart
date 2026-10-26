import 'package:flutter/material.dart';

import '../data/drive_backup.dart';
import 'backup_screen.dart';
import 'day_screen.dart';
import 'expense_form_screen.dart';
import 'month_screen.dart';
import 'sources_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _dayKey = GlobalKey<DayScreenState>();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DriveBackup.instance.maybeAutoBackup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) DriveBackup.instance.maybeAutoBackup();
  }

  void _openDay(DateTime day) {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _dayKey.currentState?.jumpTo(day));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          DayScreen(key: _dayKey),
          MonthScreen(onOpenDay: _openDay),
          const SourcesScreen(),
          const BackupScreen(),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => openExpenseForm(context, date: _dayKey.currentState?.currentDay),
              icon: const Icon(Icons.add),
              label: const Text('Thêm chi tiêu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), label: 'Theo ngày'),
          NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Theo tháng'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Nguồn tiền'),
          NavigationDestination(icon: Icon(Icons.cloud_outlined), label: 'Sao lưu'),
        ],
      ),
    );
  }
}
