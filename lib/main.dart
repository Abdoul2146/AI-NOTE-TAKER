import 'package:flutter/material.dart';
import 'package:scribesync/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
// import 'package:scribesync/screens/homeScreen.dart';
import 'package:scribesync/screens/signInScreen.dart';
import 'package:scribesync/screens/splashScreen.dart';
import 'package:scribesync/screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScribeSync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      debugShowCheckedModeBanner: false,
      // Use a StreamBuilder to listen for authentication state changes
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Show SplashScreen while Firebase is connecting or checking state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }

          // If the user data is available (user is signed in)
          if (snapshot.hasData) {
            return const MainNavigationScreen();
          }

          // If no user data, show the Sign-In screen
          return const SignInScreen();
        },
      ),
    );
  }
}
