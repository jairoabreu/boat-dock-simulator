import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/flight_provider.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'screens/setup_screen.dart';
import 'screens/history_screen.dart';
import 'screens/aircraft_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  final notif = NotificationService();
  await notif.init();

  final provider = FlightProvider(storage, notif);
  await provider.loadLastConfig();

  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const FuelBalanceApp(),
    ),
  );
}

class FuelBalanceApp extends StatelessWidget {
  const FuelBalanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel Balance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF071220),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00B0FF),
          secondary: Color(0xFF00C853),
          surface: Color(0xFF0A1A2E),
          error: Color(0xFFD50000),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFCCE3F5)),
          bodyMedium: TextStyle(color: Color(0xFF8BA7C0)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF09131F),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFFCCE3F5),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF071220),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const SetupScreen(),
        '/history': (_) => const HistoryScreen(),
        '/aircraft': (_) => const AircraftScreen(),
      },
    );
  }
}
