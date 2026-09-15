import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  final double radius;
  final bool showInitialsFallback;
  final Color? backgroundColor;

  const UserAvatar({
    super.key,
    this.radius = 18.0,
    this.showInitialsFallback = false,
    this.backgroundColor,
  });

  String _nameFromEmail(String email) {
    if (email.isEmpty) return 'User';
    final parts = email.split('@');
    final namePart = parts[0];
    final cleanName = namePart.replaceAll(RegExp(r'[0-9.\-_]'), ' ').trim();
    if (cleanName.isEmpty) return 'User';

    return cleanName.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoURL = user?.photoURL;
    final fallbackColor = backgroundColor ?? const Color(0xFF1A3528);

    if (photoURL != null && photoURL.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: fallbackColor,
        backgroundImage: CachedNetworkImageProvider(photoURL),
      );
    }

    if (showInitialsFallback && user != null) {
      final email = user.email ?? '';
      final displayName = user.displayName?.isNotEmpty == true
          ? user.displayName!
          : _nameFromEmail(email);
      final initials = _initials(displayName);

      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.greenMuted,
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: fallbackColor,
      child: Icon(Icons.person, color: Colors.white54, size: radius * 1.2),
    );
  }
}
