import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'agreement_screen.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _signUp() async {
    if (_displayNameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.isEmpty ||
        _confirmPasswordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      // Save user data to Firestore.
      // Everyone starts as a Viewer. An Officer/Moderator/Reviewer
      // promotes the account to "CAS Student" from the admin dashboard
      // once they're approved to upload films.
      try {
        await _firestore.collection('users').doc(credential.user!.uid).set({
          'displayName': _displayNameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'role': 'Viewer',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (firestoreError) {
        // The Auth account was created but the profile write failed
        // (network hiccup, permissions rule, app backgrounded, etc).
        // Without this, we'd end up with an orphaned Auth account that
        // can log in but has no users/{uid} doc -- it would show up in
        // login_logs but never in the users collection, and would
        // silently be treated as a Viewer with no role forever.
        // Roll it back so the person can just try signing up again.
        try {
          await credential.user!.delete();
        } catch (_) {
          // If delete also fails (e.g. requires recent login), there's
          // nothing more we can do client-side -- surface the original
          // error below so at least the user knows signup didn't finish.
        }
        rethrow;
      }

      // Stay signed in -- AgreementScreen's "Agree" button routes back
      // to _RoleGate (in main.dart), which will already recognize this
      // new Viewer and show PublicNavScreen -- so there's no need to
      // sign out and force a manual re-login here.
      if (!mounted) return;

      // Plain push (NOT pushAndRemoveUntil) -- _RoleGate is the very
      // first route in the app (the `home` of MaterialApp), and it's
      // the thing that listens for sign-out and automatically shows
      // LoginScreen. Removing it from the stack (which pushAndRemoveUntil
      // with `(route) => false` was doing) killed that listener for the
      // rest of the session, which is why Log Out silently did nothing
      // after creating a new account.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AgreementScreen()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create account: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B13),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          // AutofillGroup ties all the fields below together as one
          // logical form for Android's autofill service. Without this,
          // Android's autofill/Smart Lock overlay can pop up and steal
          // focus the moment you start typing in ANY field, which is
          // what was closing the keyboard and forcing a second tap.
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 36),
                Center(
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/psaulogo.png',
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'PSAUni',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      TextSpan(
                        text: 'Films',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Sign up to start watching inspiring\nstories and student documentaries.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),
                _buildTextField(
                  controller: _displayNameCtrl,
                  hint: 'Full Name',
                  prefixIcon: Icons.person_outline,
                  autofillHints: const [AutofillHints.name],
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _emailCtrl,
                  hint: 'Email',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _passwordCtrl,
                  hint: 'Password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscurePass,
                  autofillHints: const [AutofillHints.newPassword],
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _confirmPasswordCtrl,
                  hint: 'Confirm Password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscureConfirm,
                  autofillHints: const [AutofillHints.newPassword],
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D8B40),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: const Text(
                        'Log in',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    List<String>? autofillHints,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF162820),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: Icon(prefixIcon, color: Colors.white38, size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
