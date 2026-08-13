import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'manage_users_screen.dart';
import '../services/fcm_token_service.dart';

// ─── Enums & Models ───────────────────────────────────────────────────────────

enum SubmissionStatus { pending, approved, returned }

class FilmSubmission {
  final String id;
  final String title;
  final String director;
  final String studentName;
  final String uploaderId;
  final String theme;
  final int year;
  SubmissionStatus status;
  String note;
  final String colorHex;
  final String thumbnail;

  FilmSubmission({
    required this.id,
    required this.title,
    this.director = '',
    required this.studentName,
    required this.uploaderId,
    required this.theme,
    required this.year,
    required this.status,
    required this.colorHex,
    this.note = '',
    this.thumbnail = '',
  });
}

// ─── Theme Constants ──────────────────────────────────────────────────────────

const _bgDark = Color(0xFF0F1A0F);
const _bgCard = Color(0xFF1A2B1A);
const _bgCardLight = Color(0xFF1E301E);
const _green = Color(0xFF4CAF50);
const _textPrimary = Color(0xFFE8F5E9);
const _textSecondary = Color(0xFF9E9E9E);
const _pendingColor = Color(0xFFFF8F00);
const _approvedColor = Color(0xFF4CAF50);
const _returnedColor = Color(0xFFE53935);

// ─── Main Screen ──────────────────────────────────────────────────────────────

class DevcomDashboardScreen extends StatefulWidget {
  const DevcomDashboardScreen({super.key});

  @override
  State<DevcomDashboardScreen> createState() => _DevcomDashboardScreenState();
}

class _DevcomDashboardScreenState extends State<DevcomDashboardScreen> {
  int _selectedTab = 0;

  // ✅ FIX #1: created ONCE as a cached field (late final), not as a getter.
  // A getter rebuilds (and resubscribes) a brand-new Firestore listener
  // every single time setState() runs anywhere in this widget (e.g. when
  // switching tabs), which causes the moderation queue to behave
  // inconsistently and can make UI updates look like they "don't happen".
  late final Stream<List<FilmSubmission>> _submissionsStream = FirebaseFirestore
      .instance
      .collection('films')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((doc) {
            final data = doc.data();
            return FilmSubmission(
              id: doc.id,
              title: data['title'] ?? 'Untitled',
              director: data['director'] ?? '',
              studentName: data['uploaderName'] ?? 'Unknown',
              uploaderId: data['uploadedBy'] ?? '',
              theme: data['genre'] ?? 'General',
              year: (data['createdAt'] as Timestamp?)?.toDate().year ??
                  DateTime.now().year,
              status: _parseStatus(data['status']),
              colorHex: '4A7C59',
              note: data['note'] ?? '',
              thumbnail: data['thumbnail'] ?? '',
            );
          }).toList());

  static SubmissionStatus _parseStatus(String? s) => switch (s) {
        'approved' => SubmissionStatus.approved,
        'returned' => SubmissionStatus.returned,
        _ => SubmissionStatus.pending,
      };

  // ✅ FIX #2: wrapped in try/catch so failures (most commonly Firestore
  // security rules rejecting the write) are visible instead of silently
  // doing nothing. This is almost certainly why "Approve" looked like it
  // wasn't working — the write was failing and you never knew.
  Future<void> _updateStatus(
      String id, SubmissionStatus newStatus, String note, String title, String uploaderId) async {
    final statusStr = switch (newStatus) {
      SubmissionStatus.approved => 'approved',
      SubmissionStatus.returned => 'returned',
      SubmissionStatus.pending => 'pending',
    };

    try {
      final doc =
          await FirebaseFirestore.instance.collection('films').doc(id).get();
      final title = doc.data()?['title'] ?? 'A film';

      await FirebaseFirestore.instance.collection('films').doc(id).update({
        'status': statusStr,
        'note': note,
      });

      // 5. Send push notification if returning or approving
      if (newStatus == SubmissionStatus.approved) {
        // Trigger notification directly from the client without Blaze!
        sendApprovalNotification(title);
      } else if (newStatus == SubmissionStatus.returned) {
        sendReturnNotification(uploaderId, title, note);
      }

      if (!mounted) return;
      _showToast(
        newStatus == SubmissionStatus.approved
            ? '✅ Film approved!'
            : '↩ Film returned for revision',
        newStatus == SubmissionStatus.approved
            ? _approvedColor
            : _returnedColor,
      );
    } catch (e) {
      // ✅ This will print the REAL reason to your debug console.
      // Look for something like [cloud_firestore/permission-denied].
      debugPrint('❌ Failed to update film $id status to $statusStr: $e');
      if (!mounted) return;
      _showToast('❌ Update failed: $e', _returnedColor);
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

  @override
  Widget build(BuildContext context) {
    // ✅ StreamBuilder wraps everything so dashboard is always live
    return StreamBuilder<List<FilmSubmission>>(
      stream: _submissionsStream,
      builder: (context, snapshot) {
        // ✅ FIX #3: surface stream-level errors too (e.g. permission-denied
        // on the read side, or a missing Firestore index for orderBy).
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: _bgDark,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading submissions:\n${snapshot.error}',
                  style: const TextStyle(color: _returnedColor, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final submissions = snapshot.data ?? [];

        // ✅ FIX: tab 2 ("Users") now shows the REAL Firestore-backed
        // ManageUsersScreen instead of a hardcoded in-memory dummy list
        // (previously: Maria Santos, Juan Dela Cruz, etc — fake seed
        // data that never touched the actual users collection). Any
        // role change an officer makes here now actually persists and
        // affects real accounts.
        final screens = [
          _DashboardTab(
            submissions: submissions,
            onUpdateStatus: (id, status, note) => _updateStatus(
                id, status, note, submissions.firstWhere((s) => s.id == id).title, submissions.firstWhere((s) => s.id == id).uploaderId),
            onNavigateToSubmissions: () => setState(() => _selectedTab = 1),
            onNavigateToUsers: () => setState(() => _selectedTab = 2),
          ),
          _SubmissionsTab(
            submissions: submissions,
            onUpdateStatus: (id, status, note) => _updateStatus(
                id, status, note, submissions.firstWhere((s) => s.id == id).title, submissions.firstWhere((s) => s.id == id).uploaderId),
          ),
          const ManageUsersScreen(),
        ];

        return Scaffold(
          backgroundColor: _bgDark,
          body: IndexedStack(index: _selectedTab, children: screens),
          bottomNavigationBar: _BottomNav(
            selectedIndex: _selectedTab,
            onTap: (i) => setState(() => _selectedTab = i),
          ),
        );
      },
    );
  }
}

// ─── Bottom Navigation ────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Dashboard',
                  index: 0,
                  selected: selectedIndex == 0,
                  onTap: onTap),
              _NavItem(
                  icon: Icons.description_outlined,
                  label: 'Submissions',
                  index: 1,
                  selected: selectedIndex == 1,
                  onTap: onTap),
              _NavItem(
                  icon: Icons.people_outlined,
                  label: 'Users',
                  index: 2,
                  selected: selectedIndex == 2,
                  onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool selected;
  final ValueChanged<int> onTap;

  const _NavItem(
      {required this.icon,
      required this.label,
      required this.index,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _green : _textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

// ─── App Header ───────────────────────────────────────────────────────────────

class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _bgCardLight,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: _green.withValues(alpha: 0.4)),
            ),
            child:
                const Icon(Icons.movie_filter_rounded, color: _green, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(children: [
                  TextSpan(
                      text: 'PSAUni',
                      style: TextStyle(
                          color: _green,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: 'Films',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w400)),
                ]),
              ),
              const Text('Officer Dashboard',
                  style: TextStyle(color: _textSecondary, fontSize: 12)),
            ],
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_rounded, color: _textPrimary, size: 24),
            color: _bgCard,
            onSelected: (value) async {
              if (value == 'logout') {
                await FirebaseAuth.instance.signOut();
                // _RoleGate handles navigation automatically
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                  SizedBox(width: 10),
                  Text('Log Out', style: TextStyle(color: Colors.redAccent)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Film Thumbnail ───────────────────────────────────────────────────────────

class _FilmThumbnail extends StatelessWidget {
  final String colorHex;
  final String thumbnail;

  const _FilmThumbnail({required this.colorHex, this.thumbnail = ''});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('FF$colorHex', radix: 16));
    if (thumbnail.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          thumbnail,
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(color),
        ),
      );
    }
    return _placeholder(color);
  }

  Widget _placeholder(Color color) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 28),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final SubmissionStatus status;

  const _StatusBadge({required this.status});

  Color get _color => switch (status) {
        SubmissionStatus.pending => _pendingColor,
        SubmissionStatus.approved => _approvedColor,
        SubmissionStatus.returned => _returnedColor,
      };

  String get _label => switch (status) {
        SubmissionStatus.pending => 'Pending',
        SubmissionStatus.approved => 'Approved',
        SubmissionStatus.returned => 'Returned',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(_label,
          style: TextStyle(
              color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Detail / Action Modal ────────────────────────────────────────────────────

void showFilmDetailModal(
  BuildContext context,
  FilmSubmission submission,
  Future<void> Function(String id, SubmissionStatus status, String note)
      onUpdateStatus,
) {
  final noteController = TextEditingController(text: submission.note);
  String selectedTheme = submission.theme;

  showModalBottomSheet(
    context: context,
    backgroundColor: _bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: submission.thumbnail.isNotEmpty
                      ? Image.network(
                          submission.thumbnail,
                          width: double.infinity,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _placeholderBox(submission.colorHex),
                        )
                      : _placeholderBox(submission.colorHex),
                ),
                const SizedBox(height: 16),
                Text(submission.title,
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _DetailRow(label: 'Student', value: submission.studentName),
                if (submission.director.isNotEmpty)
                  _DetailRow(label: 'Director', value: submission.director),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Theme',
                          style:
                              TextStyle(color: _textSecondary, fontSize: 13)),
                      DropdownButton<String>(
                        value: [
                          'Agriculture',
                          'Culture',
                          'Environment',
                          'Education',
                          'Community'
                        ].contains(selectedTheme)
                            ? selectedTheme
                            : null,
                        hint: Text(selectedTheme,
                            style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        dropdownColor: _bgCardLight,
                        style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        underline: const SizedBox(),
                        icon: const Icon(Icons.edit,
                            color: _textSecondary, size: 16),
                        items: [
                          'Agriculture',
                          'Culture',
                          'Environment',
                          'Education',
                          'Community'
                        ]
                            .map((t) =>
                                DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (val) async {
                          if (val != null && val != selectedTheme) {
                            setModalState(() => selectedTheme = val);
                            try {
                              await FirebaseFirestore.instance
                                  .collection('films')
                                  .doc(submission.id)
                                  .update({'genre': val});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Theme updated successfully!'),
                                      backgroundColor: _approvedColor),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Failed to update theme: $e'),
                                      backgroundColor: _returnedColor),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                _DetailRow(label: 'Year', value: '${submission.year}'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status',
                          style:
                              TextStyle(color: _textSecondary, fontSize: 13)),
                      _StatusBadge(status: submission.status),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                const Text('Feedback / Revision Note',
                    style: TextStyle(color: _textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _bgCardLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: noteController,
                    maxLines: 3,
                    style: const TextStyle(color: _textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Add a note for the student...',
                      hintStyle: TextStyle(color: _textSecondary),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textPrimary,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                    if (submission.status != SubmissionStatus.returned) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            onUpdateStatus(
                                submission.id,
                                SubmissionStatus.returned,
                                noteController.text.trim());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _returnedColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('↩ Return'),
                        ),
                      ),
                    ],
                    if (submission.status != SubmissionStatus.approved) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            onUpdateStatus(
                                submission.id,
                                SubmissionStatus.approved,
                                noteController.text.trim());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('✓ Approve'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _placeholderBox(String colorHex) {
  final color = Color(int.parse('FF$colorHex', radix: 16));
  return Container(
    width: double.infinity,
    height: 140,
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12)),
    child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 48),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: _textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Moderation Card ──────────────────────────────────────────────────────────

class _ModerationCard extends StatelessWidget {
  final FilmSubmission submission;
  final Future<void> Function(String, SubmissionStatus, String) onUpdateStatus;

  const _ModerationCard(
      {required this.submission, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          _FilmThumbnail(
              colorHex: submission.colorHex, thumbnail: submission.thumbnail),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(submission.title,
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text('Student: ${submission.studentName}',
                    style:
                        const TextStyle(color: _textSecondary, fontSize: 12)),
                Text('Theme: ${submission.theme}',
                    style:
                        const TextStyle(color: _textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _ActionButton(
                      label: 'View Details',
                      color: _bgCardLight,
                      textColor: _textPrimary,
                      onTap: () => showFilmDetailModal(
                          context, submission, onUpdateStatus),
                    ),
                    _ActionButton(
                      label: '✓ Approve',
                      color: _green,
                      textColor: Colors.white,
                      onTap: () => onUpdateStatus(submission.id,
                          SubmissionStatus.approved, submission.note),
                    ),
                    _ActionButton(
                      label: '↩ Return',
                      color: _returnedColor,
                      textColor: Colors.white,
                      onTap: () => showFilmDetailModal(
                          context, submission, onUpdateStatus),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.label,
      required this.color,
      required this.textColor,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                color: textColor, fontSize: 10, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: _textPrimary, fontSize: 14))),
            const Icon(Icons.chevron_right_rounded,
                color: _textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard Tab ────────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  final List<FilmSubmission> submissions;
  final Future<void> Function(String, SubmissionStatus, String) onUpdateStatus;
  final VoidCallback onNavigateToSubmissions;
  final VoidCallback onNavigateToUsers;

  const _DashboardTab({
    required this.submissions,
    required this.onUpdateStatus,
    required this.onNavigateToSubmissions,
    required this.onNavigateToUsers,
  });

  @override
  Widget build(BuildContext context) {
    final pending =
        submissions.where((s) => s.status == SubmissionStatus.pending).toList();
    final approved = submissions
        .where((s) => s.status == SubmissionStatus.approved)
        .toList();
    final returned = submissions
        .where((s) => s.status == SubmissionStatus.returned)
        .toList();
    final queue = pending.take(3).toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AppHeader(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _StatCard(
                            label: 'Pending\nReviews',
                            value: '${pending.length}',
                            icon: Icons.inbox_rounded,
                            color: _pendingColor),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: 'Approved',
                            value: '${approved.length}',
                            icon: Icons.check_circle_outline,
                            color: _approvedColor),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: 'Returned',
                            value: '${returned.length}',
                            icon: Icons.undo_rounded,
                            color: _returnedColor),
                        const SizedBox(width: 8),
                        _StatCard(
                            label: 'Total',
                            value: '${submissions.length}',
                            icon: Icons.description_outlined,
                            color: _textSecondary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Moderation Queue',
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (queue.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('No pending submissions 🎉',
                        style: TextStyle(color: _textSecondary, fontSize: 14))),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ModerationCard(
                    submission: queue[i], onUpdateStatus: onUpdateStatus),
                childCount: queue.length,
              ),
            ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 4),
                _MenuRow(
                    icon: Icons.description_outlined,
                    label: 'View All Submissions',
                    onTap: onNavigateToSubmissions),
                _MenuRow(
                    icon: Icons.people_outlined,
                    label: 'User Management',
                    onTap: onNavigateToUsers),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: _textSecondary, fontSize: 10, height: 1.3)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(icon, color: color, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Submissions Tab ──────────────────────────────────────────────────────────

class _SubmissionsTab extends StatefulWidget {
  final List<FilmSubmission> submissions;
  final Future<void> Function(String, SubmissionStatus, String) onUpdateStatus;

  const _SubmissionsTab(
      {required this.submissions, required this.onUpdateStatus});

  @override
  State<_SubmissionsTab> createState() => _SubmissionsTabState();
}

class _SubmissionsTabState extends State<_SubmissionsTab> {
  int _filterIndex = 0;
  String _search = '';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<FilmSubmission> get _filtered {
    final statusFilter = [
      null,
      SubmissionStatus.pending,
      SubmissionStatus.approved,
      SubmissionStatus.returned
    ][_filterIndex];
    return widget.submissions.where((s) {
      final matchStatus = statusFilter == null || s.status == statusFilter;
      final matchSearch = _search.isEmpty ||
          s.title.toLowerCase().contains(_search.toLowerCase()) ||
          s.studentName.toLowerCase().contains(_search.toLowerCase());
      return matchStatus && matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const _AppHeader(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('Submissions',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (int i = 0; i < 4; i++) ...[
                  _FilterChip(
                    label: ['All', 'Pending', 'Approved', 'Returned'][i],
                    selected: _filterIndex == i,
                    onTap: () => setState(() => _filterIndex = i),
                  ),
                  if (i < 3) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: _controller,
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: _textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search submissions...',
                  hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: _textSecondary, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No submissions found',
                        style: TextStyle(color: _textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _SubmissionListTile(
                      submission: filtered[i],
                      onUpdateStatus: widget.onUpdateStatus,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

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
              color: selected ? _green : Colors.white.withValues(alpha: 0.1)),
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

class _SubmissionListTile extends StatelessWidget {
  final FilmSubmission submission;
  final Future<void> Function(String, SubmissionStatus, String) onUpdateStatus;

  const _SubmissionListTile(
      {required this.submission, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showFilmDetailModal(context, submission, onUpdateStatus),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            _FilmThumbnail(
                colorHex: submission.colorHex, thumbnail: submission.thumbnail),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(submission.title,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(submission.studentName,
                      style:
                          const TextStyle(color: _textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${submission.theme} • ${submission.year}',
                          style: const TextStyle(
                              color: _textSecondary, fontSize: 11)),
                      const SizedBox(width: 8),
                      _StatusBadge(status: submission.status),
                    ],
                  ),
                  if (submission.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Note: ${submission.note}',
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _textSecondary),
          ],
        ),
      ),
    );
  }
}
