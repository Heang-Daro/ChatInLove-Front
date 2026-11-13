import 'package:flutter/material.dart';
import 'package:love_in_chat/data/database/app_database.dart';
import 'package:love_in_chat/data/repositories/chat_repository.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/screen/HomeScreen.dart';
import 'package:love_in_chat/screen/LoginScreen.dart';
import 'package:love_in_chat/service/CacheService.dart';
import 'package:love_in_chat/service/NotificationService.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  // Prepare the local chat cache folder (offline-first data).
  await CacheService.init();
  debugPrint('APP STARTED & NOTIFICATION SERVICE INITIALIZED');

  // The local SQLite database (drift) is the source of truth for the
  // offline-first chat screens.
  final database = AppDatabase();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ConversationProvider()),
        Provider<AppDatabase>.value(value: database),
        ProxyProvider<AuthProvider, ChatRepository>(
          create: (context) => ChatRepository(
            db: database,
            auth: context.read<AuthProvider>(),
          ),
          update: (context, auth, previous) => previous ??
              ChatRepository(db: database, auth: auth),
          dispose: (context, repository) => repository.stopListening(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'In Love',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          primary: Colors.pinkAccent,
          secondary: Colors.pink.shade300,
        ),
        useMaterial3: true,
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: Colors.pink.shade100,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: Colors.pinkAccent,
                fontWeight: FontWeight.bold,
              );
            }
            return const TextStyle(color: Colors.grey);
          }),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.dark,
          primary: Colors.pinkAccent,
        ),
        useMaterial3: true,
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: Colors.pink.shade900,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: Colors.pinkAccent,
                fontWeight: FontWeight.bold,
              );
            }
            return const TextStyle(color: Colors.grey);
          }),
        ),
      ),
      // Use Consumer to dynamically switch between Login and Home based on auth state
      // Use Consumer to dynamically switch between Splash, Login, and Home
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          // 1. Show a loading state while reading SharedPreferences tokens on cold start
          if (!authProvider.isInitialized) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  color: Colors.pinkAccent,
                ),
              ),
            );
          }

          // 2. Once initialized, route based on authentication state
          if (authProvider.isAuthenticated) {
            // The device location is only sent when the user allows it. It
            // runs in the background, the app stays usable while it works.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              authProvider.syncCurrentDevice();
            });

            return HomeScreen(
              onThemeChanged: _setThemeMode,
              currentThemeMode: _themeMode,
            );
          } else {
            return LoginScreen(
              onThemeChanged: _setThemeMode,
              currentThemeMode: _themeMode,
            );
          }
        },
      ),
    );
  }
}