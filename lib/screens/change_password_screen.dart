import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  bool _isLoading = false;
  bool _emailSent = false;

  Future<void> _sendResetLink() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
      setState(() => _emailSent = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset link sent to ${user.email}')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        foregroundColor: Colors.white,
        title: const Text('Change Password'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.lock_reset, color: Color(0xFF4CAF50), size: 72),
            const SizedBox(height: 24),
            const Text('Reset your password',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('A reset link will be sent to:\n${user?.email ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 14, height: 1.6)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isLoading || _emailSent ? null : _sendResetLink,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D8B40),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white12,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(_emailSent ? 'Email Sent ✓' : 'Send Reset Link',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            if (_emailSent) ...[
              const SizedBox(height: 20),
              const Text(
                  'Check your inbox and follow the link. Check spam if you don\'t see it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white38, fontSize: 13, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}
