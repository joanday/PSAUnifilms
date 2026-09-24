import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'signup_screen.dart';

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

  List<Map<String, String>> _savedAccounts = [];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('saved_accounts');
    if (savedData != null) {
      try {
        final List<dynamic> decoded = jsonDecode(savedData);
        setState(() {
          _savedAccounts =
              decoded.map((e) => Map<String, String>.from(e)).toList();
        });
      } catch (e) {
        debugPrint('Failed to decode saved accounts: $e');
      }
    }
  }

  Future<void> _saveAccountLocally(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();

    // Check if it already exists
    final existingIndex =
        _savedAccounts.indexWhere((acc) => acc['email'] == email);
    if (existingIndex != -1) {
      _savedAccounts[existingIndex]['password'] = password;
    } else {
      _savedAccounts.add({'email': email, 'password': password});
    }

    await prefs.setString('saved_accounts', jsonEncode(_savedAccounts));
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveLoginLog(User user) async {
    try {
      await _firestore.collection('login_logs').add({
        'userId': user.uid,
        'email': user.email,
        'loginTime': FieldValue.serverTimestamp(),
        'status': 'success',
      });
    } catch (e) {
      debugPrint('Failed to save login log: $e');
    }
  }

  /// Roles are stored capitalized in Firestore (e.g. 'Viewer', 'CAS Student',
  /// 'Officer', 'Moderator', 'Reviewer') — see signup_screen.dart and
  /// manage_users_screen.dart.
  ///
  /// Self-heal: some older/interrupted signups created a Firebase Auth
  /// account but never got a matching users/{uid} doc (e.g. the Firestore
  /// write failed right after createUserWithEmailAndPassword). Those
  /// accounts could log in — showing up in login_logs — but never
  /// appeared in the users collection and always fell through to
  /// Viewer/Public with no way to fix it from the app. If we detect a
  /// missing doc here, create a default Viewer profile for them instead
  /// of leaving them permanently stuck.
  ///
  /// We still call this after login even though we no longer navigate
  /// off its result (see _onLogin below) -- its job now is purely this
  /// repair side-effect. _RoleGate (main.dart) does its own role lookup
  /// and routing once it sees the auth state change.
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

      await _saveAccountLocally(
          _emailCtrl.text.trim(), _passwordCtrl.text.trim());
      await _saveLoginLog(credential.user!);

      if (!mounted) return;

      // Run the self-heal check (repairs a missing users/{uid} doc if
      // needed) but DON'T navigate off its result anymore.
      //
      // _RoleGate in main.dart is already listening to
      // authStateChanges() and will automatically swap this LoginScreen
      // for the correct role's screen on its own the moment
      // signInWithEmailAndPassword above completes. Calling
      // Navigator.pushReplacement here used to REPLACE _RoleGate's own
      // route entirely -- which permanently killed its auth listener,
      // so Log Out later would silently do nothing.
      await _getUserRole(credential.user!);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyLoginError(e))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ CHANGED: this used to just show Firebase's own raw error message
  // (e.g. "The supplied auth credential is incorrect, malformed or has
  // expired.", or even "There is no user record corresponding to this
  // identifier."). Those raw messages are too specific for a login
  // screen -- they tell an attacker exactly WHY a login attempt failed
  // (no such account vs. wrong password vs. malformed token), which lets
  // someone try random emails and learn which ones are actually
  // registered, one at a time. A generic message that treats every
  // credential-related failure the same way is standard practice for
  // login forms. Non-credential problems (bad email format, disabled
  // account, rate limiting, no internet) are still shown clearly since
  // those don't leak anything about other people's accounts.
  String _friendlyLoginError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact the admin.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      default:
        return 'Incorrect email or password. Please try again.';
    }
  }

  void _onForgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }
    const resetMessage =
        'If that email is registered, a password reset link has been sent.';
    try {
      await _auth.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(resetMessage)),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'invalid-email') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid email address.')),
        );
        return;
      }
      // ✅ CHANGED: previously showed Firebase's raw message here too,
      // which for 'user-not-found' directly confirms an email is NOT
      // registered. Showing the exact same success-looking message
      // whether or not the account exists means "Forgot password" can no
      // longer be used to check who has an account on the app.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(resetMessage)),
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
    // ✅ CHANGED: the whole form used CrossAxisAlignment.stretch, so on a
    // phone every field/button naturally maxed out at the phone's own
    // (narrow) width -- looked fine. But now that the app fills the whole
    // browser window on desktop, "stretch" meant stretching all the way
    // to the edges of a 1500px+ window, which looked exactly like your
    // sketch: giant fields spanning almost the whole screen. Nothing about
    // the fields/buttons/text themselves changed -- same labels, same
    // icons, same everything -- this just wraps the same column in a
    // centered box that caps its width at 420px on a wide/desktop screen,
    // so it reads like a normal centered login card instead. On an actual
    // phone (width <= 600) this has no effect at all.
    final isWide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A0F),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: isWide ? 420 : double.infinity),
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
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
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
                          MaterialPageRoute(
                              builder: (_) => const SignUpScreen()),
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

                  if (_savedAccounts.isNotEmpty) ...[
                    const SizedBox(height: 48),
                    const Center(
                      child: Text(
                        'Recent Accounts',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 60,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _savedAccounts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final acc = _savedAccounts[index];
                          return GestureDetector(
                            onTap: () {
                              _emailCtrl.text = acc['email'] ?? '';
                              _passwordCtrl.text = acc['password'] ?? '';
                              _onLogin();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF162820),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Color(0xFF3D8B40),
                                    child: Icon(Icons.person,
                                        size: 16, color: Colors.white),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    acc['email'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
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
