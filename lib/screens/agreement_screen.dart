import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
                        // Pop back to _RoleGate (main.dart) instead of
                        // pushing+wiping the stack -- _RoleGate is still
                        // alive underneath (signup_screen.dart no longer
                        // destroys it), so it already knows this Viewer
                        // is signed in and will show PublicNavScreen the
                        // moment we reveal it.
                        Navigator.popUntil(context, (route) => route.isFirst);
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
                        // Declining must fully undo what signup_screen.dart
                        // just created -- just signing out isn't enough,
                        // because the Auth account + Firestore profile
                        // would still exist, so typing the same
                        // email/password on the login screen would just
                        // log back into the "declined" account instead of
                        // properly rejecting it.
                        final user = FirebaseAuth.instance.currentUser;
                        try {
                          if (user != null) {
                            final uid = user.uid;
                            try {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .delete();
                            } catch (_) {
                              // Non-fatal -- worst case an orphaned
                              // profile doc is left behind; still proceed
                              // to delete the Auth account below.
                            }
                            await user.delete();
                          }
                        } catch (_) {
                          await FirebaseAuth.instance.signOut();
                        }

                        if (!context.mounted) return;

                        // Same reasoning as Agree above: pop back to the
                        // still-alive _RoleGate rather than pushing a new
                        // LoginScreen and wiping the stack. _RoleGate will
                        // already be showing LoginScreen since the user is
                        // no longer signed in.
                        Navigator.popUntil(context, (route) => route.isFirst);
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
