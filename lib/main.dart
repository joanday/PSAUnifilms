import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/devcom_dashboard_screen.dart';
import 'screens/public_nav_screen.dart';
import 'services/notification_service.dart';

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

  runApp(const PSAUniFilmsApp());

  unawaited(NotificationService.initialize().catchError(
    (e) => debugPrint('NotificationService init error: $e'),
  ));
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
        scaffoldBackgroundColor: const Color(0xFF0F1A0F),
        primaryColor: const Color(0xFF4CAF50),
      ),
      // ✅ CHANGED: we tried a fixed-width "card" (480px, centered) here so
      // desktop wouldn't look like a stretched phone screen -- but that
      // ended up reading as a phone screenshot floating on a plain
      // background instead, which isn't what we want either. Now there's
      // no wrapper at all: the app simply fills the whole browser window,
      // Netflix-style, same as any normal website. Every screen already
      // decides its own desktop-vs-phone layout (top nav vs bottom nav,
      // how many grid columns, etc.) from its own width check, so this is
      // safe on its own -- an actual phone is completely unaffected.
      builder: (context, child) => child ?? const SizedBox.shrink(),
      home: const _RoleGate(),
    );
  }
}

/// The app now has just two roles: Admin (can upload films -- which
/// publish immediately, no separate approval step -- and manage users)
/// and Viewer (watch only). Any account still carrying an older role
/// value (Officer, Moderator, Reviewer, CAS Student -- from before this
/// simplification) is automatically downgraded to Viewer the next time
/// it logs in. Promote specific people back to Admin afterward from the
/// Manage Users screen.
class _RoleGate extends StatefulWidget {
  const _RoleGate();

  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  String? _cachedRole;
  String? _cachedUid;

  Future<String?> _fetchRole(String uid) async {
    if (_cachedUid == uid && _cachedRole != null) return _cachedRole;

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final doc = await docRef.get();

    String? role = doc.data()?['role'] as String?;

    // One-time migration: collapse every old role value down to Viewer.
    // 'Admin' passes through untouched; anything else (including a
    // missing/null role, or a leftover Officer/Moderator/Reviewer/CAS
    // Student) becomes 'Viewer'.
    if (role != 'Admin') {
      if (role != 'Viewer') {
        try {
          await docRef.set({'role': 'Viewer'}, SetOptions(merge: true));
        } catch (_) {
          // Non-fatal -- worst case this account gets re-migrated the
          // next time it logs in. Still treat it as Viewer below.
        }
      }
      role = 'Viewer';
    }

    _cachedUid = uid;
    _cachedRole = role;
    return role;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ CHANGED: authStateChanges() is a bit unreliable on Flutter Web --
    // it can silently fail to fire right after signInWithEmailAndPassword
    // completes, which is why logging in "worked" (no error, account got
    // saved) but the app stayed stuck on the Login screen until a manual
    // page refresh re-ran everything from scratch. userChanges() is the
    // more reliable stream for this on web (it also reacts to token
    // refreshes, not just sign-in/sign-out), and fixes exactly this
    // "signed in but the screen didn't switch" symptom.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        if (snapshot.hasData && snapshot.data != null) {
          final uid = snapshot.data!.uid;
          final email = snapshot.data!.email;

          // This account always stays Admin, regardless of whatever the
          // Firestore doc says.
          if (email == 'joanmarieday5@gmail.com') {
            FirebaseFirestore.instance.collection('users').doc(uid).set({
              'role': 'Admin',
              'email': email,
            }, SetOptions(merge: true));
            _cachedUid = uid;
            _cachedRole = 'Admin';
            return const DevcomDashboardScreen();
          }

          if (_cachedUid == uid && _cachedRole != null) {
            return _screenForRole(_cachedRole);
          }

          return FutureBuilder<String?>(
            future: _fetchRole(uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingScreen();
              }

              if (roleSnapshot.hasError) {
                return const _LoadingScreen();
              }

              return _screenForRole(roleSnapshot.data);
            },
          );
        }

        _cachedRole = null;
        _cachedUid = null;
        return const LoginScreen();
      },
    );
  }

  Widget _screenForRole(String? role) {
    if (role == 'Admin') {
      return const DevcomDashboardScreen();
    }
    return const PublicNavScreen();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F1A0F),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
      ),
    );
  }
}
