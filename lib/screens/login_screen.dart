import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_main_nav_screen.dart';
import 'devcom_dashboard_screen.dart';
import 'signup_screen.dart';
import 'public_nav_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _saveLoginLog(User user) async {
    await _firestore.collection('login_logs').add({
      'userId': user.uid,
      'email': user.email,
      'loginTime': FieldValue.serverTimestamp(),
      'status': 'success',
    });
  }

  /// Roles are stored capitalized in Firestore (e.g. 'Viewer', 'CAS Student',
  /// 'Officer', 'Moderator', 'Reviewer') — see signup_screen.dart and
  /// manage_users_screen.dart. Routing below must match those exact strings.
  ///
  /// Self-heal: some older/interrupted signups created a Firebase Auth
  /// account but never got a matching users/{uid} doc (e.g. the Firestore
  /// write failed right after createUserWithEmailAndPassword). Those
  /// accounts could log in — showing up in login_logs — but never
  /// appeared in the users collection and always fell through to
  /// Viewer/Public with no way to fix it from the app. If we detect a
  /// missing doc here, create a default Viewer profile for them instead
  /// of leaving them permanently stuck.
  Future<String?> _getUserRole(User user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (doc.exists) {
        return doc.data()?['role'] as String?;
      }

      // Missing profile — repair it now.
      await docRef.set({
        'displayName': user.displayName ?? (user.email ?? 'Unknown'),
        'email': user.email,
        'role': 'Viewer',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return 'Viewer';
    } catch (_) {}
    return null;
  }

  void _onLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      await _saveLoginLog(credential.user!);

      if (!mounted) return;

      final role = await _getUserRole(credential.user!);

      if (!mounted) return;

      if (role == 'Officer' || role == 'Moderator' || role == 'Reviewer') {
        // Staff → dashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DevcomDashboardScreen()),
        );
      } else if (role == 'CAS Student') {
        // Officer-promoted → can submit films
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentMainNavScreen()),
        );
      } else {
        // Viewer / everyone else → watch only
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PublicNavScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onForgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B13),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 36),

              // ── Logo ──────────────────────────────────────────────────────
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

              // ── Title ─────────────────────────────────────────────────────
              const Text(
                'Welcome to',
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

              // ── Subtitle ──────────────────────────────────────────────────
              const Text(
                'Log in to continue watching inspiring\nstories and student documentaries.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              // ── Email field ───────────────────────────────────────────────
              _buildTextField(
                controller: _emailCtrl,
                hint: 'Email',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 14),

              // ── Password field ────────────────────────────────────────────
              _buildTextField(
                controller: _passwordCtrl,
                hint: 'Password',
                prefixIcon: Icons.lock_outline,
                obscureText: _obscurePass,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),

              const SizedBox(height: 14),

              // ── Forgot password ───────────────────────────────────────────
              Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: _onForgotPassword,
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Log In button ─────────────────────────────────────────────
              ElevatedButton(
                onPressed: _isLoading ? null : _onLogin,
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
                        'Log In',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),

              const SizedBox(height: 24),

              // ── Sign up link ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    ),
                    child: const Text(
                      'Sign up',
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
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