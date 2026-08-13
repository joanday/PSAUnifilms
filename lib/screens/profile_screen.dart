import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/film.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'account_settings_screen.dart';
import 'change_password_screen.dart';
import 'film_detail_screen.dart';
import 'my_submissions_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _loadNotificationPref();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() {
          _userRole = doc.data()?['role'] as String?;
        });
      }
    }
  }

  Future<void> _loadNotificationPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _toggleNotifications(bool enabled) async {
    setState(() => _notificationsEnabled = enabled);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);

    final user = FirebaseAuth.instance.currentUser;

    if (enabled) {
      await FirebaseMessaging.instance.subscribeToTopic('new_uploads');
      if (user != null) {
        await FirebaseMessaging.instance.subscribeToTopic('user_${user.uid}');
      }
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic('new_uploads');
      if (user != null) {
        await FirebaseMessaging.instance.unsubscribeFromTopic('user_${user.uid}');
      }
    }
  }

  String _nameFromEmail(String email) {
    final local = email.split('@').first;
    return local
        .split('.')
        .map((w) => w.isNotEmpty
            ? w[0].toUpperCase() + w.substring(1).toLowerCase()
            : '')
        .join(' ');
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  void _showHelpSupport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Help & Support',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            const Text('For assistance, contact us at:',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            const Text('support@psaunifilms.com',
                style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('We typically respond within 24 hours.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: controller,
            children: const [
              Text('Privacy Policy',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: 16),
              Text(
                'PSAUniFilms is committed to protecting your privacy. '
                'We collect only the information necessary to provide our services, '
                'including your email address and viewing preferences.\n\n'
                'Your data is never sold to third parties. '
                'We use Firebase services to securely store your account information.\n\n'
                'You may request deletion of your account and data at any time '
                'by contacting our support team.\n\n'
                'By using PSAUniFilms, you agree to this privacy policy.',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Log Out?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context); // close dialog first
                await FirebaseAuth.instance.signOut();
                // _RoleGate in main.dart listens to authStateChanges()
                // and will automatically show LoginScreen — no need
                // for manual navigation which was causing the delay.
              },
              child: const Text('Log Out',
                  style: TextStyle(color: AppTheme.redDecline))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final displayName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : _nameFromEmail(email);
    final initials = _initials(displayName);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F17),
        title: const Text('Profile & Settings',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Avatar ──────────────────────────────────────────────────────
          Center(
            child: Column(children: [
              const SizedBox(height: 12),
              Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.greenMuted,
                    child: Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700)),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                          color: AppTheme.greenPrime,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF0D1F17), width: 2)),
                      child: const Icon(Icons.camera_alt_outlined,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(displayName,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text(email,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
            ]),
          ),
          // ── Account ──────────────────────────────────────────────────────
          _sectionLabel('Account'),
          _settingsCard([
            _tile(Icons.person_outline, 'Account Settings', onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AccountSettingsScreen()));
            }),
            _tile(Icons.lock_outline, 'Change Password', onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen()));
            }),
            if (_userRole == 'CAS Student' || _userRole == 'cas_student')
              _tile(Icons.video_library_outlined, 'My Submissions', onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MySubmissionsScreen()));
              }),
          ]),

          const SizedBox(height: 16),

          // ── Preferences ──────────────────────────────────────────────────
          // Note: "Download Quality" and "Subtitles" were moved to
          // watch_screen.dart (accessible via the settings icon in the
          // player's app bar) so they're reachable while actually
          // streaming, instead of being buried here.
          _sectionLabel('Preferences'),
          _settingsCard([
            _tile(
              Icons.notifications_outlined,
              'Notifications',
              trailing: Switch(
                value: _notificationsEnabled,
                onChanged: _toggleNotifications,
                activeThumbColor: AppTheme.greenPrime,
              ),
              onTap: () => _toggleNotifications(!_notificationsEnabled),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Support ──────────────────────────────────────────────────────
          _sectionLabel('Support'),
          _settingsCard([
            _tile(Icons.help_outline, 'Help & Support',
                onTap: _showHelpSupport),
            _tile(Icons.privacy_tip_outlined, 'Privacy Policy',
                onTap: _showPrivacyPolicy),
            _tile(Icons.info_outline, 'About PSAUniFilms',
                subtitle: 'v1.0.0', onTap: () {}),
          ]),

          const SizedBox(height: 16),

          // ── Log Out ──────────────────────────────────────────────────────
          _settingsCard([
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.redDecline),
              title: const Text('Log Out',
                  style: TextStyle(
                      color: AppTheme.redDecline, fontWeight: FontWeight.w500)),
              onTap: _showLogoutDialog,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w500)),
      );

  static Widget _settingsCard(List<Widget> tiles) => Container(
        decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor)),
        child: Column(
          children: tiles.asMap().entries.map((e) {
            final isLast = e.key == tiles.length - 1;
            return Column(children: [
              e.value,
              if (!isLast)
                const Divider(
                    height: 0, color: AppTheme.borderColor, indent: 52),
            ]);
          }).toList(),
        ),
      );

  static Widget _tile(
    IconData icon,
    String title, {
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) =>
      ListTile(
        leading: Icon(icon, color: AppTheme.textMuted, size: 22),
        title: Text(title,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))
            : null,
        trailing: trailing ??
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 20),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}

