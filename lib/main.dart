import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/student_main_nav_screen.dart';
import 'screens/devcom_dashboard_screen.dart';
import 'screens/public_nav_screen.dart';
import 'services/notification_service.dart';

// Must be a top-level function (outside any class) so Firebase can call it
// when a notification arrives while the app is fully closed/terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();

  runApp(const PSAUniFilmsApp());
}

class PSAUniFilmsApp extends StatelessWidget {
  const PSAUniFilmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PSAUniFilms',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1F17),
        primaryColor: const Color(0xFF4CAF50),
      ),
      home: const _RoleGate(), // moved to stateful widget
    );
  }
}

// Stateful widget caches the role so it never re-fetches on Navigator.pop
class _RoleGate extends StatefulWidget {
  const _RoleGate();

  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  String? _cachedRole;
  String? _cachedUid;

  Future<String?> _fetchRole(String uid) async {
    // Return cached role if same user
    if (_cachedUid == uid && _cachedRole != null) return _cachedRole;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    final role = doc.data()?['role'] as String?;
    _cachedUid = uid;
    _cachedRole = role;
    return role;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        if (snapshot.hasData && snapshot.data != null) {
          final uid = snapshot.data!.uid;
          final email = snapshot.data!.email;

          // Temporary bypass to ensure the user gets their Officer account
          if (email == 'joanmarieday5@gmail.com') {
            FirebaseFirestore.instance.collection('users').doc(uid).set({
              'role': 'Officer',
              'email': email,
            }, SetOptions(merge: true));
            return const DevcomDashboardScreen();
          }

          // If role already cached for this user, go straight to screen
          if (_cachedUid == uid && _cachedRole != null) {
            return _screenForRole(_cachedRole);
          }

          return FutureBuilder<String?>(
            future: _fetchRole(uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingScreen();
              }

              // If the role fetch failed or the user doc doesn't exist
              // yet (e.g. right after signup, before Firestore write
              // settles), don't silently fall through to the student
              // screen — show a safe loading/retry state instead of
              // routing somewhere that assumes data which isn't there.
              if (roleSnapshot.hasError) {
                return const _LoadingScreen();
              }

              return _screenForRole(roleSnapshot.data);
            },
          );
        }

        // Clear cache on logout
        _cachedRole = null;
        _cachedUid = null;
        return const LoginScreen();
      },
    );
  }

  Widget _screenForRole(String? role) {
    // Roles are stored capitalized in Firestore: 'Officer', 'Moderator',
    // 'Reviewer', 'CAS Student', 'Viewer' — must match exactly, and every
    // branch must be handled explicitly. Falling through to the student
    // screen by default would let a plain Viewer reach the submit flow.
    if (role == 'Officer' || role == 'Moderator' || role == 'Reviewer' || role == 'officer') {
      return const DevcomDashboardScreen();
    }

    if (role == 'CAS Student' || role == 'cas_student') {
      return const StudentMainNavScreen();
    }

    // Viewer, null, or any unrecognized role → public/watch-only view
    return const PublicNavScreen();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D1F17),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
      ),
    );
  }
}
