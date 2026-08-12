import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'public_nav_screen.dart';
import 'login_screen.dart';

class AgreementScreen extends StatelessWidget {
  const AgreementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),

                    // Logo
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFB8960C), width: 2),
                        color: const Color(0xFF1A3528),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/psaulogo.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    const Text(
                      'User Agreement –',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'PSAUniFilms',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Body text
                    const Text(
                      'Welcome to PSAUniFilms. We are proud to present student films and showcase CAS DEVCOM documentaries from Pampanga State Agricultural University. This application is a platform for archiving and viewing these valuable works for educational use only. Users are expected to act responsibly and respect the content.',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 16),

                    // Bullet points
                    _bullet(
                        'The documentaries on this platform are for educational use only.'),
                    _bullet(
                        'Users agree not to redistribute, re-upload, or post to social media without prior permission.'),
                    const SizedBox(height: 16),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'By proceeding, you agree to these terms.',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                children: [
                  // Agree
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        // signup_screen.dart now keeps the user signed in,
                        // and every new signup is created with role:
                        // 'Viewer' — so it's safe to route straight to
                        // PublicNavScreen without a role lookup here.
                        // If an officer later promotes this account to
                        // 'CAS Student', that only takes effect on their
                        // NEXT login (via _RoleGate in main.dart), not
                        // retroactively in this already-open session.
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PublicNavScreen()),
                          (route) => false,
                        );
                      },
                      child: const Text('Agree'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Decline
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () async {
                        // The user is already signed in to Firebase Auth
                        // by the time they reach this screen (see
                        // signup_screen.dart). Declining the agreement
                        // means they should NOT remain authenticated —
                        // otherwise _RoleGate in main.dart will just log
                        // them back in automatically on next launch.
                        //
                        // We also can't rely on Navigator.pop(context)
                        // here: the route that led to this screen may
                        // have been pushed with pushAndRemoveUntil,
                        // which clears everything below it, leaving
                        // nothing underneath to pop back to (this was
                        // causing the black screen bug).
                        await FirebaseAuth.instance.signOut();

                        if (!context.mounted) return;

                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.5)),
            ),
          ],
        ),
      );
}
