import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/film.dart';
import '../services/ai_service.dart';
import '../services/bunny_service.dart';
import '../widgets/custom_video_player.dart';
import '../widgets/star_rating.dart';
import '../utils/genres.dart';

// ─── Admin-only: edit a single documentary ───────────────────────────────────
//
// Opened by tapping a row in EditDocumentariesScreen. Layout, top to bottom:
// video playback, an editable Title (pencil icon), a Description field with
// a pencil icon beside it to toggle editing, a "Retry AI" button, a "Save"
// button that applies the edited title/description for everyone, and a
// Danger Zone with a permanent Delete button (center popup + countdown).

class EditDocumentaryScreen extends StatefulWidget {
  final String filmId;
  const EditDocumentaryScreen({super.key, required this.filmId});

  @override
  State<EditDocumentaryScreen> createState() => _EditDocumentaryScreenState();
}

class _EditDocumentaryScreenState extends State<EditDocumentaryScreen> {
  late final DocumentReference _filmRef =
      FirebaseFirestore.instance.collection('films').doc(widget.filmId);

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _descLoaded = false;
  bool _editingTitle = false;
  bool _editingDescription = false;
  // ✅ NEW: the genre/theme tags were shown as plain static text with no
  // way to change them -- if the uploader picked the wrong theme(s) at
  // upload time, there was no way to fix it afterward. Editable the same
  // way as Title/Description (pencil icon toggles a chip picker, same
  // multi-select chips as Submit Film).
  final Set<String> _selectedGenres = {};
  bool _editingGenres = false;
  bool _isRetryingAi = false;
  bool _isSaving = false;
  bool _isDeleting = false;

  // ── Video playback (so this feels like actually watching the doc, same
  // as FilmDetailScreen, instead of just a static thumbnail) ──────────────
  final GlobalKey _videoPlayerKey = GlobalKey();
  int? _videoStatus;
  bool _checkingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkVideoStatus();
  }

  Future<void> _checkVideoStatus() async {
    try {
      final doc = await _filmRef.get();
      final data = doc.data() as Map<String, dynamic>?;
      final videoUrl = data?['videoUrl'] as String? ?? '';
      if (videoUrl.isEmpty) {
        if (mounted) setState(() => _checkingStatus = false);
        return;
      }
      final uri = Uri.parse(videoUrl);
      final segments = uri.pathSegments;
      if (segments.length >= 2) {
        final guid = segments[segments.length - 2];
        final statusData = await BunnyService.getVideoStatus(guid);
        if (mounted) {
          setState(() {
            _videoStatus = statusData['status'] as int;
            _checkingStatus = false;
          });
        }
      } else {
        if (mounted) setState(() => _checkingStatus = false);
      }
    } catch (e) {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Widget _buildVideoHeader(Film film) {
    final hasVideo = film.videoUrl.isNotEmpty;

    if (!hasVideo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: AppTheme.bgCard,
            child: const Center(
                child: Icon(Icons.movie_outlined,
                    color: AppTheme.textMuted, size: 40)),
          ),
        ),
      );
    }

    if (_checkingStatus) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: const Center(
                child: CircularProgressIndicator(color: AppTheme.greenPrime)),
          ),
        ),
      );
    }

    if (_videoStatus != null && _videoStatus! < 3) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_empty, color: Colors.white70, size: 40),
                  SizedBox(height: 12),
                  Text('Video is processing on the server...',
                      style: TextStyle(color: Colors.white70)),
                  Text('Please check back in a few minutes.',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomVideoPlayer(
        key: _videoPlayerKey,
        videoUrl: film.videoUrl,
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _retryAi(Film film) async {
    setState(() => _isRetryingAi = true);
    try {
      final currentTitle = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : film.title;
      final currentDescription = _descController.text.trim().isNotEmpty
          ? _descController.text.trim()
          : film.description;
      final aiData = await AiService.generateMetadata(
        currentTitle,
        currentDescription,
        visualDescription: film.visualDescription,
      );
      await _filmRef.update({
        'aiSummary': aiData.summary,
        'aiKeywords': aiData.keywords,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI insights regenerated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Retry AI failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isRetryingAi = false);
    }
  }

  Future<void> _save() async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title cannot be empty.')),
      );
      return;
    }
    if (_selectedGenres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select at least one theme/genre.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // This is what "ma-a-apply sa lahat" means here: the films collection
      // doc is the single source of truth every screen (Watch, Search,
      // FilmDetailScreen) reads from, so updating it here is immediately
      // reflected everywhere for everyone. 'genre' (singular) is kept in
      // sync as the first-selected tag for backward compatibility with any
      // older code path that still reads it, same as Submit Film does.
      await _filmRef.update({
        'title': newTitle,
        'description': _descController.text.trim(),
        'genres': _selectedGenres.toList(),
        'genre': _selectedGenres.first,
      });
      if (mounted) {
        setState(() {
          _editingTitle = false;
          _editingDescription = false;
          _editingGenres = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Changes saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Permanent delete, with a center "danger" popup that makes the admin
  // wait out a short countdown before the Delete button becomes pressable
  // -- so an accidental double-tap can't delete something by mistake. This
  // removes the films/{id} record entirely (not reversible).
  Future<void> _confirmDelete(Film film) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteConfirmDialog(title: film.title),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _filmRef.delete();
      if (mounted) {
        Navigator.of(context).pop(); // back to the Edit Documentary Videos list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documentary permanently deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ NEW: on a wide (desktop/Chrome) window this screen used to stretch
    // the video, title and description full edge-to-edge, which is why the
    // title/description looked cut off/misaligned against the window sides.
    // Now it matches the same centered, max-640-wide layout already used on
    // Submit Film, Profile, Manage Users and Watchlist. On an actual phone
    // (width <= 600) this has zero effect: the layout stays exactly as it
    // was.
    final isWide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1A0F),
        title: const Text('Edit Documentary',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _filmRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.greenPrime));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text('This documentary no longer exists.',
                  style: TextStyle(color: AppTheme.textMuted)),
            );
          }

          final film = Film.fromFirestore(snapshot.data!);

          // Only seed the title/description fields once (on first load), so
          // we don't overwrite whatever the admin is actively typing every
          // time Firestore pushes a fresh snapshot back down this stream.
          if (!_descLoaded) {
            _titleController.text = film.title;
            _descController.text = film.description;
            _selectedGenres
              ..clear()
              ..addAll(film.genres.isNotEmpty ? film.genres : [film.genre]);
            _descLoaded = true;
          }

          return Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Video playback (watch it right here while editing) ─────
                  _buildVideoHeader(film),
                  const SizedBox(height: 16),

                  // ── Title (pencil icon toggles editing) ─────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _editingTitle
                            ? TextField(
                                controller: _titleController,
                                autofocus: true,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: AppTheme.bgCard,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: AppTheme.borderColor),
                                  ),
                                ),
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  _titleController.text.isNotEmpty
                                      ? _titleController.text
                                      : film.title,
                                  style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _editingTitle = !_editingTitle),
                        icon: Icon(
                            _editingTitle ? Icons.check : Icons.edit_outlined,
                            color: AppTheme.greenPrime,
                            size: 20),
                        tooltip: _editingTitle ? 'Done editing' : 'Edit title',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${film.year}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 13)),

                  const SizedBox(height: 16),

                  // ── Theme / Genre (pencil icon toggles a chip picker,
                  // same multi-select chips as Submit Film) ────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('THEME / GENRE',
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0)),
                      IconButton(
                        onPressed: () =>
                            setState(() => _editingGenres = !_editingGenres),
                        icon: Icon(
                            _editingGenres ? Icons.check : Icons.edit_outlined,
                            color: AppTheme.greenPrime,
                            size: 20),
                        tooltip: _editingGenres
                            ? 'Done editing'
                            : 'Edit theme/genre',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _editingGenres
                      ? Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: kGenres.map((genreInfo) {
                            final selected =
                                _selectedGenres.contains(genreInfo.label);
                            return FilterChip(
                              selected: selected,
                              onSelected: (isSelected) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedGenres.add(genreInfo.label);
                                  } else {
                                    _selectedGenres.remove(genreInfo.label);
                                  }
                                });
                              },
                              avatar: Icon(genreInfo.icon,
                                  size: 18,
                                  color:
                                      selected ? Colors.white : Colors.white54),
                              label: Text(genreInfo.label),
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : Colors.white70,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              backgroundColor: const Color(0xFF1A3528),
                              selectedColor: const Color(0xFF2E7D52),
                              checkmarkColor: Colors.white,
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFF2E5C3E),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            );
                          }).toList(),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (_selectedGenres.isNotEmpty
                                  ? _selectedGenres
                                  : {film.genre})
                              .map((g) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.bgCard,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppTheme.borderColor),
                                    ),
                                    child: Text(g,
                                        style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 12)),
                                  ))
                              .toList(),
                        ),

                  const SizedBox(height: 16),

                  // ── Rating + views (streamed live from films/{filmId},
                  // same widget FilmDetailScreen uses, so this always
                  // matches what viewers see) ────────────────────────────
                  StarRating(filmId: widget.filmId),

                  const SizedBox(height: 24),

                  // ── Description (pencil icon toggles editing) ─────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('DESCRIPTION',
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0)),
                      IconButton(
                        onPressed: () => setState(
                            () => _editingDescription = !_editingDescription),
                        icon: Icon(
                            _editingDescription
                                ? Icons.check
                                : Icons.edit_outlined,
                            color: AppTheme.greenPrime,
                            size: 20),
                        tooltip: _editingDescription
                            ? 'Done editing'
                            : 'Edit description',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _editingDescription
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.borderColor),
                          ),
                          child: TextField(
                            controller: _descController,
                            maxLines: 6,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 14),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.all(12),
                              border: InputBorder.none,
                              hintText: 'Describe this documentary...',
                              hintStyle: TextStyle(color: AppTheme.textMuted),
                            ),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.borderColor),
                          ),
                          child: Text(
                            _descController.text.isNotEmpty
                                ? _descController.text
                                : 'No description yet.',
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                height: 1.5),
                          ),
                        ),

                  const SizedBox(height: 24),

                  // ── Retry AI ────────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isRetryingAi ? null : () => _retryAi(film),
                      icon: _isRetryingAi
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.greenPrime))
                          : const Icon(Icons.auto_awesome_outlined,
                              color: AppTheme.greenPrime),
                      label: Text(
                        _isRetryingAi ? 'Regenerating...' : 'Retry AI',
                        style: const TextStyle(color: AppTheme.greenPrime),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.greenPrime),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Re-runs the AI summary and search keywords used by Smart Search (CBVR), based on the current title and description.',
                    style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 11, height: 1.4),
                  ),

                  const SizedBox(height: 32),

                  // ── Save (applies the edited description for everyone) ────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.greenPrime,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Danger Zone: permanent delete ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DANGER ZONE',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        const Text(
                          'Permanently deletes this documentary, its Firestore record, rating, comments and watchlist entries. This cannot be undone.',
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                _isDeleting ? null : () => _confirmDelete(film),
                            icon: _isDeleting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.red))
                                : const Icon(Icons.delete_forever_outlined,
                                    color: Colors.red),
                            label: Text(
                              _isDeleting ? 'Deleting...' : 'Delete Video',
                              style: const TextStyle(color: Colors.red),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Center "danger" confirmation popup with a safety countdown ─────────────
//
// The Delete button inside this dialog starts disabled and shows a
// countdown ("Delete (5)", "Delete (4)"...); it only becomes pressable once
// the countdown reaches zero. This stops an admin from reflexively tapping
// through a confirmation popup and deleting something by accident.

class _DeleteConfirmDialog extends StatefulWidget {
  final String title;
  const _DeleteConfirmDialog({required this.title});

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  static const _startSeconds = 5;
  int _secondsLeft = _startSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _secondsLeft == 0;

    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 30),
          ),
          const SizedBox(height: 12),
          const Text('Delete this documentary?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.red,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
        ],
      ),
      content: Text(
        '"${widget.title}" will be permanently deleted. This cannot be undone -- the film record, its rating, comments and watchlist entries will all be gone.',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: AppTheme.textMuted, fontSize: 13, height: 1.5),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child:
              const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            disabledBackgroundColor: Colors.red.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(
            canDelete ? 'Delete Permanently' : 'Delete ($_secondsLeft)',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
