import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Theme Constants (mirrors devcom_dashboard_screen.dart) ──────────────────
// NOTE: these are re-declared here because the ones in the dashboard file are
// private (underscore-prefixed) and not importable across files.

const _bgDark = Color(0xFF0F1A0F);
const _bgCard = Color(0xFF1A2B1A);
const _bgCardLight = Color(0xFF1E301E);
const _green = Color(0xFF4CAF50);
const _textPrimary = Color(0xFFE8F5E9);
const _textSecondary = Color(0xFF9E9E9E);

// ─── Role enum ─────────────────────────────────────────────────────────────

enum UserRole { viewer, casStudent, officer }

UserRole _parseRole(String? s) => switch (s) {
      'Officer' || 'officer' => UserRole.officer,
      'CAS Student' || 'cas_student' => UserRole.casStudent,
      _ => UserRole.viewer,
    };

String _roleToString(UserRole r) => switch (r) {
      UserRole.officer => 'Officer',
      UserRole.casStudent => 'CAS Student',
      UserRole.viewer => 'Viewer',
    };

String _roleLabel(UserRole r) => switch (r) {
      UserRole.officer => 'Officer',
      UserRole.casStudent => 'CAS Student',
      UserRole.viewer => 'Viewer',
    };

Color _roleColor(UserRole r) => switch (r) {
      UserRole.officer => const Color(0xFF4CAF50),
      UserRole.casStudent => const Color(0xFF2196F3),
      UserRole.viewer => const Color(0xFF9E9E9E),
    };

// ─── Model ─────────────────────────────────────────────────────────────────

class AppUser {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String photoUrl;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl = '',
  });
}

// ─── Screen ────────────────────────────────────────────────────────────────

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  // Same pattern as the dashboard's submissions stream: created ONCE as a
  // cached late-final field so switching tabs / rebuilding this widget
  // doesn't spin up a new Firestore listener every time.
  late final Stream<List<AppUser>> _usersStream = FirebaseFirestore.instance
      .collection('users')
      // .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs.map((doc) {
            final data = doc.data();
            return AppUser(
              id: doc.id,
              name: data['name'] ?? data['displayName'] ?? 'Unnamed User',
              email: data['email'] ?? '',
              role: _parseRole(data['role']),
              photoUrl: data['photoUrl'] ?? '',
            );
          }).toList());

  String _search = '';
  int _filterIndex = 0; // 0 = All, 1 = Viewer, 2 = CAS Student, 3 = Officer

  Future<void> _updateRole(String userId, UserRole newRole) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'role': _roleToString(newRole)});

      if (!mounted) return;
      _showToast('✅ Role updated to ${_roleLabel(newRole)}', _green);
    } catch (e) {
      debugPrint('❌ Failed to update role for $userId: $e');
      if (!mounted) return;
      _showToast('❌ Update failed: $e', const Color(0xFFE53935));
    }
  }

  void _showToast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  void _openRoleSheet(AppUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(user.name,
                  style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(user.email,
                  style: const TextStyle(color: _textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              const Text('Set Role',
                  style: TextStyle(color: _textSecondary, fontSize: 13)),
              const SizedBox(height: 10),
              for (final role in UserRole.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (role != user.role) {
                        _updateRole(user.id, role);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: role == user.role
                            ? _roleColor(role).withOpacity(0.15)
                            : _bgCardLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: role == user.role
                              ? _roleColor(role)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: _roleColor(role),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Text(_roleLabel(role),
                              style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          const Spacer(),
                          if (role == user.role)
                            Icon(Icons.check_circle_rounded,
                                color: _roleColor(role), size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: _usersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: _bgDark,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading users:\n${snapshot.error}',
                  style:
                      const TextStyle(color: Color(0xFFE53935), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: _bgDark,
            body: Center(child: CircularProgressIndicator(color: _green)),
          );
        }

        final allUsers = snapshot.data!;
        final roleFilter = [
          null,
          UserRole.viewer,
          UserRole.casStudent,
          UserRole.officer,
        ][_filterIndex];

        final filtered = allUsers.where((u) {
          final matchRole = roleFilter == null || u.role == roleFilter;
          final q = _search.toLowerCase();
          final matchSearch = q.isEmpty ||
              u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q);
          return matchRole && matchSearch;
        }).toList();

        return Scaffold(
          backgroundColor: _bgDark,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('User Management',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: const TextStyle(color: _textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search by name or email...',
                        hintStyle:
                            TextStyle(color: _textSecondary, fontSize: 14),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: _textSecondary, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (int i = 0; i < 4; i++) ...[
                        _FilterChip(
                          label: ['All', 'Viewer', 'CAS Student', 'Officer'][i],
                          selected: _filterIndex == i,
                          onTap: () => setState(() => _filterIndex = i),
                        ),
                        if (i < 3) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('No users found',
                              style: TextStyle(color: _textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _UserTile(
                            user: filtered[i],
                            onTap: () => _openRoleSheet(filtered[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Small widgets ─────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _green : _bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _green : Colors.white.withOpacity(0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _bgCardLight,
              backgroundImage:
                  user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
              child: user.photoUrl.isEmpty
                  ? Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(user.email,
                      style:
                          const TextStyle(color: _textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _roleColor(user.role).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_roleLabel(user.role),
                  style: TextStyle(
                      color: _roleColor(user.role),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: _textSecondary),
          ],
        ),
      ),
    );
  }
}
