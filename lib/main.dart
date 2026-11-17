import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:love_in_chat/data/database/app_database.dart';
import 'package:love_in_chat/data/repositories/chat_repository.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/screen/HomeScreen.dart';
import 'package:love_in_chat/screen/LoginScreen.dart';
import 'package:love_in_chat/service/CacheService.dart';
import 'package:love_in_chat/service/CallKitService.dart';
import 'package:love_in_chat/service/ChatAppearanceService.dart';
import 'package:love_in_chat/service/NotificationService.dart';
import 'package:provider/provider.dart';

// Top-level function for background FCM messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Handling a background message: ${message.messageId}');
}

void main() async {
  // ថែទាំការผูก Binding ឱ្យបានត្រឹមត្រូវ
  WidgetsFlutterBinding.ensureInitialized();

  // ផ្ទៀងផ្ទាត់ និង Initialize Firebase ឱ្យបានម៉ត់ចត់
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('[Firebase] Initialized successfully in main.');
  } catch (e) {
    debugPrint('[Firebase] Initialization error: $e');
  }

  // ដំណើរការ Services ផ្សេងៗស្របគ្នា (Concurrent Initialization)
  await Future.wait([
    NotificationService.initialize(),
    CacheService.init(),
    ChatAppearanceService.initialize(),
  ]);

  debugPrint('APP STARTED & ALL SERVICES INITIALIZED SUCCESSFULLY');

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
          update: (context, auth, previous) =>
          previous ?? ChatRepository(db: database, auth: auth),
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

  void _setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // ប្រាកដថា CallKitService មាន navigatorKey នេះ
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
              return const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold);
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
              return const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold);
            }
            return const TextStyle(color: Colors.grey);
          }),
        ),
      ),
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (!authProvider.isInitialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
            );
          }
          if (authProvider.isAuthenticated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              authProvider.syncCurrentDevice();
            });
            return HomeScreen(
              onThemeChanged: _setThemeMode,
              currentThemeMode: _themeMode,
            );
          }
          return LoginScreen(
            onThemeChanged: _setThemeMode,
            currentThemeMode: _themeMode,
          );
        },
      ),
    );
  }
}