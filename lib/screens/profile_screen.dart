import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'account_settings_screen.dart';
import 'change_password_screen.dart';
import 'my_submissions_screen.dart';
import 'watchlist_screen.dart';
import 'edit_documentaries_screen.dart';

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
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
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
        await FirebaseMessaging.instance
            .unsubscribeFromTopic('user_${user.uid}');
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

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppTheme.greenPrime),
              title: const Text('Upload New Picture',
                  style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage();
              },
            ),
            if (FirebaseAuth.instance.currentUser?.photoURL != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppTheme.redDecline),
                title: const Text('Remove Picture',
                    style: TextStyle(color: AppTheme.redDecline)),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    // Declared outside the try block so the catch block below can still
    // see it (a variable declared inside try isn't visible in its catch).
    BuildContext? rootDialogContext;
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) return;

      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
              toolbarTitle: 'Crop Picture',
              toolbarColor: AppTheme.bgCard,
              toolbarWidgetColor: AppTheme.greenPrime,
              activeControlsWidgetColor: AppTheme.greenPrime,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              hideBottomControls: false),
          IOSUiSettings(
            title: 'Crop Picture',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (croppedFile == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Show loading indicator
      // ✅ CHANGED: showDialog() defaults to putting the dialog on the
      // app's ROOT navigator (not whichever nested tab navigator this
      // screen happens to live inside), so the old `Navigator.pop(context)`
      // below -- which used THIS screen's own context -- was closing the
      // wrong navigator's route and silently doing nothing, leaving this
      // loading spinner stuck on screen forever. Now we keep a handle to
      // the dialog's OWN context (rootDialogContext) and pop THAT one
      // instead, so it always closes the right thing regardless of what
      // navigator this screen is nested inside.
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            rootDialogContext = dialogContext;
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.greenPrime));
          },
        );
      }

      final storageRef =
          FirebaseStorage.instance.ref().child('users/${user.uid}/avatar.jpg');
      await storageRef.putFile(File(croppedFile.path));
      final downloadUrl = await storageRef.getDownloadURL();

      await user.updatePhotoURL(downloadUrl);

      if (rootDialogContext != null) {
        Navigator.pop(rootDialogContext!); // Close loading dialog
      }
      if (mounted) {
        setState(() {}); // Refresh UI
      }
    } catch (e) {
      if (rootDialogContext != null) {
        Navigator.pop(rootDialogContext!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload image: $e')));
      }
    }
  }

  Future<void> _removeAvatar() async {
    // Same fix as _pickAndUploadImage above -- declared outside try so
    // catch can still see it.
    BuildContext? rootDialogContext;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            rootDialogContext = dialogContext;
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.greenPrime));
          },
        );
      }

      try {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('users/${user.uid}/avatar.jpg');
        await storageRef.delete();
      } catch (e) {
        // Ignore if file doesn't exist
      }

      await user.updatePhotoURL(null);

      if (rootDialogContext != null) {
        Navigator.pop(rootDialogContext!); // Close loading dialog
      }
      if (mounted) {
        setState(() {}); // Refresh UI
      }
    } catch (e) {
      if (rootDialogContext != null) {
        Navigator.pop(rootDialogContext!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove image: $e')));
      }
    }
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
            const Text('psaunifilms.support@gmail.com',
                style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('We typically respond within 24 hours.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.greenPrime.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.info_outline,
                      color: AppTheme.greenPrime),
                ),
                const SizedBox(width: 12),
                const Text('About PSAUniFilms',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('App Purpose',
                style: TextStyle(
                    color: AppTheme.greenPrime,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            const Text(
                'PSAUniFilms was developed as a Capstone Project for the DevCom/CAS department of Pampanga State Agricultural University. It serves as a modern, centralized digital archive designed to preserve, showcase, and semantically search student-produced documentaries.',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            const Text('The Developers',
                style: TextStyle(
                    color: AppTheme.greenPrime,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
            const SizedBox(height: 12),
            _developerRow('Mimosa B. Costales', 'Lead UI Designer'),
            const SizedBox(height: 12),
            _developerRow('Joan Marie Y. Day', 'Backend Developer'),
            const SizedBox(height: 12),
            _developerRow('Sherry Herns M. Cruz', 'Project Manager'),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _developerRow(String name, String role) {
    return Row(
      children: [
        const Icon(Icons.person, color: AppTheme.textMuted, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(name,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        Text(role,
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic)),
      ],
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

  // ✅ FIXED: this was the cause of the "Log Out?" popup staying stuck on
  // screen, floating over the Login page after logging out. showDialog()
  // puts the popup on the app's ROOT navigator by default, but the
  // buttons below were calling `Navigator.pop(context)` using THIS
  // screen's own context -- which belongs to the nested tab navigator
  // Profile lives inside, not the root one. That pop was closing the
  // wrong navigator (silently doing nothing), so the popup was never
  // actually dismissed -- it just LOOKED closed for a moment because the
  // screen underneath it changed to the Login page the instant sign-out
  // completed. Now both buttons use the dialog's own context
  // (dialogContext) instead, so they always close the actual popup.
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Log Out?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext); // close dialog first
                await FirebaseAuth.instance.signOut();
                // _RoleGate in main.dart listens to userChanges() and
                // will automatically show LoginScreen — no need for
                // manual navigation which was causing the delay.
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

    // ✅ CHANGED: per the reference mockup, the settings list is just
    // centered on the plain page background now -- no bordered/tinted
    // "card" box around it. On an actual phone (width <= 600) this has no
    // effect: same plain full-width list as before.
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      // ✅ CHANGED: was 0xFF0D1F17 -- now 0xFF0F1A0F, matching
      // manage_users_screen.dart's page background exactly (Watch/Users/
      // Upload/Profile all share one uniform background color now).
      backgroundColor: const Color(0xFF0F1A0F),
      // ✅ CHANGED: dropped the AppBar title -- see submit_screen.dart for
      // the same reasoning. "Profile & Settings" is now a heading inside
      // the centered column instead, matching the "User Management"
      // heading's style/position exactly.
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: double.infinity,
                    child: Text('Profile & Settings',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 16),
                  // ── Avatar ──────────────────────────────────────────────────────
                  Center(
                    child: Column(children: [
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _showAvatarOptions,
                        child: Stack(
                          children: [
                            const UserAvatar(
                                radius: 48, showInitialsFallback: true),
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
                                        color: const Color(0xFF0D1F17),
                                        width: 2)),
                                child: const Icon(Icons.camera_alt_outlined,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(displayName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text(email,
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 13)),
                      const SizedBox(height: 16),
                    ]),
                  ),
                  // ── Account ──────────────────────────────────────────────────────
                  _sectionLabel('Account'),
                  _settingsCard([
                    // ✅ Admin-only: lets Admin open, edit and archive/unarchive any
                    // uploaded documentary (title, description, AI tags via Retry
                    // AI) without needing a separate old-style moderation screen.
                    if (_userRole == 'Admin')
                      _tile(Icons.movie_creation_outlined,
                          'Edit Documentary Videos', onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const EditDocumentariesScreen()));
                      }),
                    // ✅ Admin-only too: regular Viewers already have their own
                    // dedicated Watchlist tab in the bottom nav, so this would just
                    // be a redundant duplicate for them. Admin has no Watchlist tab
                    // (it was moved out to keep that nav focused), so it stays here
                    // for Admin only.
                    if (_userRole == 'Admin')
                      _tile(Icons.bookmark_outline, 'My Watchlist', onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const WatchlistScreen()));
                      }),
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
                    if (_userRole == 'CAS Student' ||
                        _userRole == 'cas_student')
                      _tile(Icons.video_library_outlined, 'My Submissions',
                          onTap: () {
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
                        subtitle: 'v1.0.0', onTap: _showAbout),
                  ]),

                  const SizedBox(height: 16),

                  // ── Log Out ──────────────────────────────────────────────────────
                  _settingsCard([
                    ListTile(
                      leading:
                          const Icon(Icons.logout, color: AppTheme.redDecline),
                      title: const Text('Log Out',
                          style: TextStyle(
                              color: AppTheme.redDecline,
                              fontWeight: FontWeight.w500)),
                      onTap: _showLogoutDialog,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                    ),
                  ]),

                  const SizedBox(height: 32),
                  const Center(
                    child: Text(
                      '© 2026 PSAUniFilms. All rights reserved.',
                      style: TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
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

  static Widget _settingsCard(List<Widget> tiles) => Material(
        color: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.borderColor)),
        clipBehavior: Clip.antiAlias,
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
