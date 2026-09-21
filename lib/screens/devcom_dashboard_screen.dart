import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'manage_users_screen.dart';
import 'watch_screen.dart';
import '../services/fcm_token_service.dart';
import '../services/bunny_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

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
  final String description;
  final bool isOldDocumentary;
  String cbvrStatus;
  String cbvrError;
  int cbvrProgress;
  final String? videoUrl;

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
    this.description = '',
    this.isOldDocumentary = false,
    this.cbvrStatus = '',
    this.cbvrError = '',
    this.cbvrProgress = 0,
    this.videoUrl,
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

// ─── Shared Bunny.net status helpers ──────────────────────────────────────────
// Used by BOTH the "Approve" flow and the "Retry AI"/"Re-analyze" flow so
// they can never disagree about whether a video is actually ready.

/// Fetches the Bunny.net encode status for a film's video, given its
/// videoUrl. Returns null if the URL is missing/unparseable or the request
/// fails — callers should treat null as "couldn't determine, proceed with
/// caution" rather than blocking the user forever.
Future<Map<String, dynamic>?> _fetchBunnyStatus(String? videoUrl) async {
  if (videoUrl == null) return null;
  try {
    final uri = Uri.parse(videoUrl);
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      final guid = segments[segments.length - 2];
      return await BunnyService.getVideoStatus(guid);
    }
  } catch (e) {
    debugPrint('Error checking video status: $e');
  }
  return null;
}

/// Bunny.net status codes below 3 mean the video is still queued/encoding
/// (not yet watchable end-to-end). This is the same threshold the Approve
/// flow already used.
bool _isBunnyStillProcessing(Map<String, dynamic> statusData) {
  final status = statusData['status'] as int;
  return status >= 0 && status < 3;
}

void _showStillProcessingDialog(BuildContext context, int progress) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title:
          const Text('Still Processing', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.greenPrime),
          const SizedBox(height: 20),
          Text(
            'The video is still being processed on the server.\n\nCurrent Progress: $progress%',
            style: const TextStyle(color: Colors.white70, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK', style: TextStyle(color: AppTheme.greenPrime)),
        ),
      ],
    ),
  );
}

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
  //
  // Because this stream is global to the whole DevcomDashboardScreen (not
  // scoped to a single tab/screen), any Firestore write the backend makes
  // to a film's cbvrStatus/cbvrProgress — e.g. while a re-embed or AI
  // analysis job is running on the server — is picked up live no matter
  // which tab the officer is currently looking at. Switching tabs does
  // NOT cancel or pause any in-flight Cloud Function call; those run on
  // Firebase's servers independently of what the client app is doing.
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
              thumbnail: data['thumbnailUrl'] ?? data['thumbnail'] ?? '',
              description: data['description'] ?? '',
              isOldDocumentary: data['isOldDocumentary'] ?? false,
              cbvrStatus: data['cbvrStatus'] ?? '',
              cbvrError: data['cbvrError'] ?? '',
              cbvrProgress: (data['cbvrProgress'] ?? 0) is int
                  ? (data['cbvrProgress'] ?? 0)
                  : 0,
              videoUrl: data['videoUrl'] as String?,
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
  Future<void> _updateStatus(String id, SubmissionStatus newStatus, String note,
      String title, String uploaderId) async {
    final statusStr = switch (newStatus) {
      SubmissionStatus.approved => 'approved',
      SubmissionStatus.returned => 'returned',
      SubmissionStatus.pending => 'pending',
    };

    try {
      final doc =
          await FirebaseFirestore.instance.collection('films').doc(id).get();
      final title = doc.data()?['title'] ?? 'A film';

      // Check if video is finished processing on Bunny.net before approving
      if (newStatus == SubmissionStatus.approved) {
        final videoUrl = doc.data()?['videoUrl'] as String?;
        final statusData = await _fetchBunnyStatus(videoUrl);
        if (statusData != null) {
          if (_isBunnyStillProcessing(statusData)) {
            if (!mounted) return;
            final progress = statusData['encodeProgress'];
            _showStillProcessingDialog(context, progress is int ? progress : 0);
            return; // Abort approval
          } else if (statusData['status'] == 5) {
            if (!mounted) return;
            _showToast('❌ Cannot approve: Video processing failed on server.',
                Colors.red);
            return; // Abort approval
          }
        }
      }

      await FirebaseFirestore.instance.collection('films').doc(id).update({
        'status': statusStr,
        'note': note,
      });

      // 5. Send push notification if returning or approving
      if (newStatus == SubmissionStatus.approved) {
        // Trigger notification directly from the client without Blaze!
        final isOld = doc.data()?['isOldDocumentary'] ?? false;
        if (!isOld) {
          sendApprovalNotification(title);
        }
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

  // ✅ NEW: deletes a film submission entirely from Firestore. Always
  // confirms first since this is destructive and can't be undone from
  // within the app. Note: this only removes the Firestore record — the
  // actual video file stays on Bunny.net's storage unless removed there
  // separately.
  Future<void> _deleteFilm(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _bgCard,
        title: const Text('Delete Submission?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete "$title" and its review history. This cannot be undone.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child:
                const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: _returnedColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('films').doc(id).delete();
      if (!mounted) return;
      _showToast('🗑 "$title" deleted.', _returnedColor);
    } catch (e) {
      debugPrint('❌ Failed to delete film $id: $e');
      if (!mounted) return;
      _showToast('❌ Delete failed: $e', _returnedColor);
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
                id,
                status,
                note,
                submissions.firstWhere((s) => s.id == id).title,
                submissions.firstWhere((s) => s.id == id).uploaderId),
            onDelete: _deleteFilm,
            onNavigateToSubmissions: () => setState(() => _selectedTab = 1),
            onNavigateToUsers: () => setState(() => _selectedTab = 2),
          ),
          _SubmissionsTab(
            submissions: submissions,
            onUpdateStatus: (id, status, note) => _updateStatus(
                id,
                status,
                note,
                submissions.firstWhere((s) => s.id == id).title,
                submissions.firstWhere((s) => s.id == id).uploaderId),
            onDelete: _deleteFilm,
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
              shape: BoxShape.circle,
              border: Border.all(color: _green.withValues(alpha: 0.4)),
              image: const DecorationImage(
                image: AssetImage('assets/images/psaulogo.png'),
                fit: BoxFit.cover,
              ),
            ),
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
        child: CachedNetworkImage(
          imageUrl: thumbnail,
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(color),
          errorWidget: (_, __, ___) => _placeholder(color),
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

// ─── CBVR (AI analysis) progress badge ─────────────────────────────────────────
// Small live indicator usable in cards/list tiles so officers can see that a
// film's AI analysis is still running (and how far along it is) without
// having to keep the film's detail modal open. Because it reads straight
// off the FilmSubmission that comes from the global Firestore stream, this
// updates live no matter which tab is currently showing.

class _CbvrProgressBadge extends StatelessWidget {
  final FilmSubmission submission;

  const _CbvrProgressBadge({required this.submission});

  @override
  Widget build(BuildContext context) {
    final status = submission.cbvrStatus;
    if (status.isEmpty || status == 'completed') return const SizedBox.shrink();

    final isFailed = status == 'failed';
    final label = switch (status) {
      'failed' => '❌ AI Analysis Failed',
      'waiting' => '⏳ Waiting for video to encode...',
      'downloading' => '⬇️ Preparing video...',
      'uploading' => '☁️ Uploading video to AI... ${submission.cbvrProgress}%',
      'analyzing' => '🧠 AI analyzing... ${submission.cbvrProgress}%',
      _ => '⏳ Processing... ${submission.cbvrProgress}%',
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isFailed)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: _pendingColor),
              ),
            ),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: isFailed ? _returnedColor : _pendingColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail / Action Modal ────────────────────────────────────────────────────

void showFilmDetailModal(
  BuildContext context,
  FilmSubmission submission,
  Future<void> Function(String id, SubmissionStatus status, String note)
      onUpdateStatus, {
  Future<void> Function(String id, String title)? onDelete,
}) {
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
                // Thumbnail — tap to preview the video before deciding.
                // ✅ NEW: officers no longer have to approve blind; tapping
                // opens the same player students use to watch approved
                // films, so a review can include actually watching it.
                GestureDetector(
                  onTap: submission.videoUrl == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WatchScreen(
                                videoUrl: submission.videoUrl!,
                                title: submission.title,
                                description: submission.description.isNotEmpty
                                    ? submission.description
                                    : 'Directed by ${submission.director.isNotEmpty ? submission.director : submission.studentName} • ${submission.theme} • ${submission.year}',
                              ),
                            ),
                          ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: submission.thumbnail.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: submission.thumbnail,
                                width: double.infinity,
                                height: 140,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    _placeholderBox(submission.colorHex),
                                errorWidget: (_, __, ___) => Container(
                                  width: double.infinity,
                                  height: 140,
                                  color: Color(int.parse(
                                          'FF${submission.colorHex}',
                                          radix: 16))
                                      .withValues(alpha: 0.2),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.movie_creation_outlined,
                                          color: Colors.white54, size: 32),
                                      SizedBox(height: 8),
                                      Text('Processing...',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              )
                            : _placeholderBox(submission.colorHex),
                      ),
                      if (submission.videoUrl != null)
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 1.5),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 36),
                        ),
                    ],
                  ),
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
                // ✅ NEW: shows the description the student wrote at
                // submission time — previously stored in Firestore but
                // never read into the app or shown to officers.
                if (submission.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Description',
                      style: TextStyle(color: _textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    submission.description,
                    style: const TextStyle(
                        color: _textPrimary, fontSize: 13, height: 1.4),
                  ),
                ],
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
                if (submission.cbvrStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('AI Video Analysis (Smart Search)',
                                style: TextStyle(
                                    color: _textSecondary, fontSize: 13)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (submission.cbvrStatus != 'completed' &&
                                    submission.cbvrStatus != 'failed')
                                  const SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5, color: _pendingColor),
                                  ),
                                if (submission.cbvrStatus != 'completed' &&
                                    submission.cbvrStatus != 'failed')
                                  const SizedBox(width: 6),
                                Expanded(
                                  child: (submission.cbvrStatus == 'waiting' ||
                                          submission.cbvrStatus ==
                                              'downloading')
                                      ? _PreparingVideoText(
                                          submission: submission)
                                      : Text(
                                          (() {
                                            switch (submission.cbvrStatus) {
                                              case 'completed':
                                                return '✅ AI Insight Ready';
                                              case 'failed':
                                                return '❌ AI Analysis Failed';
                                              case 'analyzing':
                                                return '🧠 AI is watching the video... ${submission.cbvrProgress}%';
                                              case 'uploading':
                                                return '☁️ Uploading video to AI... ${submission.cbvrProgress}%';
                                              default:
                                                return '⏳ Processing...';
                                            }
                                          })(),
                                          style: TextStyle(
                                              color: submission.cbvrStatus ==
                                                      'failed'
                                                  ? _returnedColor
                                                  : submission.cbvrStatus ==
                                                          'completed'
                                                      ? _approvedColor
                                                      : _pendingColor,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // ✅ NEW: don't even attempt AI analysis if the
                          // video itself isn't done encoding on Bunny.net
                          // yet — this is exactly what was causing
                          // "AI Analysis Failed" when tapped too early.
                          final statusData =
                              await _fetchBunnyStatus(submission.videoUrl);
                          if (statusData != null &&
                              _isBunnyStillProcessing(statusData)) {
                            final progress = statusData['encodeProgress'];
                            if (ctx.mounted) {
                              _showStillProcessingDialog(
                                  ctx, progress is int ? progress : 0);
                            }
                            return; // Abort — video not ready yet
                          }

                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Starting AI analysis...'),
                                  backgroundColor: _pendingColor),
                            );
                            Navigator.pop(ctx);
                            // ✅ NEW: explicit longer timeout so a
                            // slow-but-still-running
                            // server-side analysis isn't misreported as
                            // "Failed" on the client just because the
                            // default callable timeout was too short.
                            // Note: closing this modal / switching tabs
                            // does NOT cancel the Cloud Function — it
                            // keeps running on Firebase's servers, and the
                            // live Firestore stream will reflect its
                            // progress/result regardless of which screen
                            // you're on.
                            final callable =
                                FirebaseFunctions.instance.httpsCallable(
                              'retryCBVRMetadata',
                              options: HttpsCallableOptions(
                                  timeout: const Duration(seconds: 300)),
                            );
                            await callable.call({'filmId': submission.id});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('AI Analysis complete!'),
                                    backgroundColor: _approvedColor),
                              );
                            }
                          } catch (e) {
                            // ✅ FIX: previously showed an empty "Failed: "
                            // message with no actual error — now shows the
                            // real reason.
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Failed: $e'),
                                    backgroundColor: _returnedColor),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.smart_toy_outlined, size: 16),
                        label: Text(submission.cbvrStatus == 'completed'
                            ? 'Re-analyze'
                            : 'Retry AI'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A2B1A),
                          foregroundColor: _approvedColor,
                          side: const BorderSide(color: _approvedColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white12),
                ],
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
                          child: const Text('📤 Send Note & Return'),
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
                // ✅ NEW: destructive action, kept visually separate from
                // Approve/Return so it's not tapped by accident. Always
                // confirms before actually deleting (see _deleteFilm).
                if (onDelete != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onDelete(submission.id, submission.title);
                      },
                      icon: const Icon(Icons.delete_outline,
                          color: _returnedColor, size: 18),
                      label: const Text('Delete Submission',
                          style: TextStyle(
                              color: _returnedColor,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
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
  final Future<void> Function(String, String)? onDelete;

  const _ModerationCard(
      {required this.submission, required this.onUpdateStatus, this.onDelete});

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
                // ✅ NEW: live AI-analysis progress, visible from the
                // Dashboard queue without opening the detail modal.
                _CbvrProgressBadge(submission: submission),
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
                          context, submission, onUpdateStatus,
                          onDelete: onDelete),
                    ),
                    // ✅ NEW: quick preview straight from the queue, no
                    // need to open the full detail modal first.
                    if (submission.videoUrl != null)
                      _ActionButton(
                        label: '▶ Preview',
                        color: _bgCardLight,
                        textColor: _approvedColor,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WatchScreen(
                              videoUrl: submission.videoUrl!,
                              title: submission.title,
                              description: submission.description.isNotEmpty
                                  ? submission.description
                                  : 'Directed by ${submission.director.isNotEmpty ? submission.director : submission.studentName} • ${submission.theme} • ${submission.year}',
                            ),
                          ),
                        ),
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
                          context, submission, onUpdateStatus,
                          onDelete: onDelete),
                    ),
                    // ✅ NEW: quick delete straight from the queue.
                    if (onDelete != null)
                      _ActionButton(
                        label: '🗑',
                        color: _bgCardLight,
                        textColor: _returnedColor,
                        onTap: () => onDelete!(submission.id, submission.title),
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
  final Future<void> Function(String, String)? onDelete;
  final VoidCallback onNavigateToSubmissions;
  final VoidCallback onNavigateToUsers;

  const _DashboardTab({
    required this.submissions,
    required this.onUpdateStatus,
    this.onDelete,
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
                    submission: queue[i],
                    onUpdateStatus: onUpdateStatus,
                    onDelete: onDelete),
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
  final Future<void> Function(String, String)? onDelete;

  const _SubmissionsTab(
      {required this.submissions, required this.onUpdateStatus, this.onDelete});

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
                      onDelete: widget.onDelete,
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
  final Future<void> Function(String, String)? onDelete;

  const _SubmissionListTile(
      {required this.submission, required this.onUpdateStatus, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showFilmDetailModal(context, submission, onUpdateStatus,
          onDelete: onDelete),
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
                  // ✅ NEW: live AI-analysis progress, visible from the
                  // All Submissions list without opening the detail modal.
                  _CbvrProgressBadge(submission: submission),
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

class _PreparingVideoText extends StatefulWidget {
  final FilmSubmission submission;
  const _PreparingVideoText({required this.submission});

  @override
  State<_PreparingVideoText> createState() => _PreparingVideoTextState();
}

class _PreparingVideoTextState extends State<_PreparingVideoText> {
  int _progress = 0;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    if (widget.submission.cbvrStatus == 'waiting' ||
        widget.submission.cbvrStatus == 'downloading') {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (widget.submission.videoUrl == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final uri = Uri.parse(widget.submission.videoUrl!);
      final segments = uri.pathSegments;
      if (segments.length >= 2) {
        final guid = segments[segments.length - 2];
        final data = await BunnyService.getVideoStatus(guid);
        if (mounted) {
          setState(() {
            _progress = data['encodeProgress'] ?? 0;
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.submission.cbvrStatus == 'downloading') {
      return Text(
          '⬇️ Preparing video...${!_loading && _progress > 0 ? " $_progress%" : ""}',
          style: const TextStyle(
              color: _pendingColor, fontSize: 13, fontWeight: FontWeight.w600));
    }
    return Text(
      _loading
          ? '⏳ Waiting for video to encode...'
          : '⏳ Waiting for video to encode... $_progress%',
      style: const TextStyle(
          color: _pendingColor, fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
