import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/film.dart';
import '../widgets/custom_video_player.dart';
import '../services/ai_service.dart';
import '../services/bunny_service.dart';
import '../widgets/comment_section.dart';
import '../widgets/star_rating.dart';

class FilmDetailScreen extends StatefulWidget {
  final Film film;
  const FilmDetailScreen({super.key, required this.film});
  @override
  State<FilmDetailScreen> createState() => _FilmDetailScreenState();
}

class _FilmDetailScreenState extends State<FilmDetailScreen> {
  bool _inWatchlist = false;
  bool _loadingWatchlist = true;
  bool _isRegeneratingAi = false;
  bool _isRegeneratingVisual = false;
  final GlobalKey _videoPlayerKey = GlobalKey();

  int? _videoStatus;
  bool _checkingStatus = true;
  late String _localAiSummary;
  late List<String> _localAiKeywords;
  bool _isSummaryExpanded = true;

  // ✅ NEW: usage-analytics logging. _viewLogId is filled in once
  // _logViewStarted's Firestore write finishes, so _logViewCompleted (if it
  // fires later) knows which view_logs doc to mark completed.
  String? _viewLogId;

  Future<void> _logViewStarted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('films')
          .doc(widget.film.id)
          .update({'viewCount': FieldValue.increment(1)});

      final logRef =
          await FirebaseFirestore.instance.collection('view_logs').add({
        'userId': user.uid,
        'filmId': widget.film.id,
        'timestamp': FieldValue.serverTimestamp(),
        'completed': false,
      });
      _viewLogId = logRef.id;
    } catch (e) {
      debugPrint('Failed to log view start: $e');
    }
  }

  Future<void> _logViewCompleted() async {
    try {
      await FirebaseFirestore.instance
          .collection('films')
          .doc(widget.film.id)
          .update({'completedViewCount': FieldValue.increment(1)});

      if (_viewLogId != null) {
        await FirebaseFirestore.instance
            .collection('view_logs')
            .doc(_viewLogId)
            .update({'completed': true});
      }
    } catch (e) {
      debugPrint('Failed to log view completion: $e');
    }
  }

  bool get _canEdit {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == widget.film.uploadedBy ||
        (FirebaseAuth.instance.currentUser?.email?.endsWith('@psau.edu.ph') ??
            false);
  }

  Future<void> _showEditAiInsightsDialog(
      String currentSummary, List<String> currentKeywords) async {
    final summaryController = TextEditingController(text: currentSummary);
    final keywordsController =
        TextEditingController(text: currentKeywords.join(', '));

    await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: const Text('Edit AI Insights',
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: summaryController,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Summary',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.greenPrime)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: keywordsController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Keywords (comma separated)',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.greenPrime)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.greenPrime),
                onPressed: () async {
                  final newSummary = summaryController.text.trim();
                  final newKeywords = keywordsController.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();

                  await FirebaseFirestore.instance
                      .collection('films')
                      .doc(widget.film.id)
                      .update({
                    'aiSummary': newSummary,
                    'aiKeywords': newKeywords,
                    'cbvrData.transcriptSummary': newSummary,
                    'cbvrData.searchKeywords': newKeywords,
                  });

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
  }

  Future<void> _regenerateAi() async {
    setState(() => _isRegeneratingAi = true);
    try {
      final aiData = await AiService.generateMetadata(
        widget.film.title,
        widget.film.description,
        visualDescription: widget.film.visualDescription,
      );
      await FirebaseFirestore.instance
          .collection('films')
          .doc(widget.film.id)
          .update({
        'aiSummary': aiData.summary,
        'aiKeywords': aiData.keywords,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('AI Insights regenerated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to regenerate: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegeneratingAi = false);
    }
  }

  Future<void> _regenerateVisual() async {
    setState(() => _isRegeneratingVisual = true);
    try {
      final videoUrl = widget.film.videoUrl;
      if (videoUrl.isEmpty) throw Exception('No video linked.');

      // Try to construct thumbnail URL
      String thumbnailUrl = videoUrl;
      if (thumbnailUrl.contains('/video.m3u8')) {
        thumbnailUrl = thumbnailUrl.replaceAll('/video.m3u8', '/thumbnail.jpg');
      } else if (thumbnailUrl.contains('/play.m3u8')) {
        thumbnailUrl = thumbnailUrl.replaceAll('/play.m3u8', '/thumbnail.jpg');
      }

      final visualDesc =
          await AiService.generateVisualDescription(thumbnailUrl);
      await FirebaseFirestore.instance
          .collection('films')
          .doc(widget.film.id)
          .update({'visualDescription': visualDesc});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visual analysis updated for CBVR!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Visual analysis failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegeneratingVisual = false);
    }
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  late Future<List<Film>> _relatedFuture;

  DocumentReference get _watchlistRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('watchlist')
      .doc(widget.film.id);

  @override
  void initState() {
    super.initState();
    _localAiSummary = widget.film.aiSummary;
    _localAiKeywords = List.from(widget.film.aiKeywords);
    _checkWatchlist();
    _checkVideoStatus();
    _relatedFuture = _fetchRelated();
  }

  // Older films (uploaded before multi-genre tagging existed) only have the
  // singular 'genre' field saved in Firestore -- they never got a 'genres'
  // array field written to their document at all. Firestore's
  // arrayContainsAny only matches docs that actually HAVE that array field,
  // so a genres-only query misses those older films (and, the other way
  // around, viewing one of those older films and querying by its
  // (fallback, in-memory-only) genres list would still find newer films
  // just fine, since newer films DO have the array field -- this is why the
  // "no related" issue only showed up one direction). Fetching by both the
  // 'genres' array AND the singular 'genre' field and merging the results
  // covers old and new films regardless of which one you're currently
  // viewing.
  Future<List<Film>> _fetchRelated() async {
    final genres = widget.film.genres.isNotEmpty
        ? widget.film.genres
        : [widget.film.genre];
    final queryGenres = genres.length > 10 ? genres.sublist(0, 10) : genres;

    final results = await Future.wait([
      FirebaseFirestore.instance
          .collection('films')
          .where('genres', arrayContainsAny: queryGenres)
          .limit(12)
          .get(),
      FirebaseFirestore.instance
          .collection('films')
          .where('genre', whereIn: queryGenres)
          .limit(12)
          .get(),
    ]);

    final Map<String, Film> merged = {};
    for (final snap in results) {
      for (final doc in snap.docs) {
        if (doc.id == widget.film.id) continue;
        merged[doc.id] = Film.fromFirestore(doc);
      }
    }
    return merged.values.take(12).toList();
  }

  Future<void> _checkVideoStatus() async {
    if (widget.film.videoUrl.isEmpty) {
      setState(() => _checkingStatus = false);
      return;
    }

    try {
      final uri = Uri.parse(widget.film.videoUrl);
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
        setState(() => _checkingStatus = false);
      }
    } catch (e) {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Future<void> _checkWatchlist() async {
    try {
      final doc = await _watchlistRef.get();
      if (mounted) {
        setState(() {
          _inWatchlist = doc.exists;
          _loadingWatchlist = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingWatchlist = false);
    }
  }

  Future<void> _toggleWatchlist() async {
    setState(() => _loadingWatchlist = true);
    try {
      if (_inWatchlist) {
        await _watchlistRef.delete();
      } else {
        // NOTE: 'rating' and 'ratingCount' here are only a snapshot taken
        // at the moment the film is saved to the watchlist -- they do NOT
        // stay in sync afterward. The watchlist LIST screen should re-fetch
        // (or stream) the live films/{filmId} doc for display rather than
        // trusting these copied fields, the same way StarRating now does
        // on this detail screen.
        await _watchlistRef.set({
          'filmId': widget.film.id,
          'title': widget.film.title,
          'genre': widget.film.genre,
          'year': widget.film.year,
          'rating': widget.film.rating,
          'ratingCount': widget.film.ratingCount,
          'description': widget.film.description,
          'videoUrl': widget.film.videoUrl,
          'thumbnailUrl': widget.film.thumbnailUrl,
          'uploadedBy': widget.film.uploadedBy,
          'uploaderName': widget.film.uploaderName,
          'status': widget.film.status,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        setState(() {
          _inWatchlist = !_inWatchlist;
          _loadingWatchlist = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingWatchlist = false);
    }
  }

  // ✅ NEW: "Related / More from PSAUniFilms" horizontal carousel, per the
  // reference mockup. Pulls other films in the same genre (falls back to
  // just excluding this film if that comes up empty), and tapping one
  // opens ITS OWN detail screen the same way the Home grid does.
  final ScrollController _relatedScrollController = ScrollController();

  void _scrollRelated(double delta) {
    if (!_relatedScrollController.hasClients) return;
    final target = (_relatedScrollController.offset + delta)
        .clamp(0.0, _relatedScrollController.position.maxScrollExtent);
    _relatedScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _openFilm(Film film) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FilmDetailScreen(film: film)),
    );
  }

  @override
  void dispose() {
    _relatedScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: we previously auto-switched to a video-only "immersive" layout
    // based on device orientation + screen size, but that heuristic isn't
    // reliable on Flutter Web (browser/OS display scaling can make a
    // maximized desktop window look "phone landscape" in logical pixels).
    // The scrollable layout below is now always used; CustomVideoPlayer's
    // own fullscreen button handles the "big video" experience instead.

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.film.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Meta tags
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metaTag('${widget.film.year}'),
            for (final g in (widget.film.genres.isNotEmpty
                ? widget.film.genres
                : [widget.film.genre]))
              _metaTag(g),
          ],
        ),
        const SizedBox(height: 10),

        // Director
        if (widget.film.director.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.person, color: AppTheme.textMuted, size: 16),
                const SizedBox(width: 6),
                Text(
                  'The Producers: ${widget.film.director}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 4),
        // Streams the live films/{filmId} doc internally, so it
        // always shows the real average/count no matter where
        // this screen was opened from (home, watchlist, search).
        StarRating(filmId: widget.film.id),
        const SizedBox(height: 16),

        // Watchlist Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  _inWatchlist ? AppTheme.greenPrime : AppTheme.textPrimary,
              side: BorderSide(
                color:
                    _inWatchlist ? AppTheme.greenPrime : AppTheme.borderColor,
              ),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _loadingWatchlist ? null : _toggleWatchlist,
            icon: _loadingWatchlist
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.greenPrime,
                    ),
                  )
                : Icon(
                    _inWatchlist
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 18,
                  ),
            label: Text(_inWatchlist ? 'Saved' : '+ Watchlist'),
          ),
        ),
        const SizedBox(height: 20),

        // Smart Toggle: About vs AI Insight
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('films')
              .doc(widget.film.id)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data == null) return const SizedBox.shrink();

            final aiSummary = data['aiSummary'] as String? ?? '';
            final aiKeywords = (data['aiKeywords'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];

            final cbvrData = data['cbvrData'] as Map<String, dynamic>?;
            final cbvrSummary = cbvrData?['transcriptSummary'] as String?;
            final cbvrKeywords = (cbvrData?['searchKeywords'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList();

            final displaySummary =
                (cbvrSummary != null && cbvrSummary.trim().isNotEmpty)
                    ? cbvrSummary
                    : aiSummary;
            final displayKeywords =
                (cbvrKeywords != null && cbvrKeywords.isNotEmpty)
                    ? cbvrKeywords
                    : aiKeywords;

            final bool hasError =
                displaySummary.toLowerCase().contains('error') ||
                    displaySummary.toLowerCase().contains('timed out') ||
                    displaySummary.toLowerCase().contains('failed') ||
                    displaySummary.toLowerCase().contains('exception') ||
                    (displaySummary.isEmpty && displayKeywords.isEmpty);

            // NEW LOGIC: Check description accuracy
            final cbvrMetadata = data['cbvrMetadata'] as Map<String, dynamic>?;

            // Default to TRUE if cbvrMetadata is missing (e.g. still processing or never processed)
            // This prevents the description from disappearing right after upload.
            final isAccurate =
                cbvrMetadata?['isDescriptionAccurate'] as bool? ?? true;

            // If accurate (and not empty), show original About. Otherwise show AI Insight.
            final showAbout =
                isAccurate && widget.film.description.trim().isNotEmpty;

            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAbout) ...[
                    const Text('About',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),
                    Text(widget.film.description,
                        style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 14,
                            height: 1.5)),
                    const SizedBox(height: 24),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF132A1D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.greenPrime.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome,
                                      color: AppTheme.greenPrime, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('AI Insights',
                                      style: TextStyle(
                                          color: AppTheme.greenPrime,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16)),
                                ],
                              ),
                              if (_canEdit)
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.white54, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _showEditAiInsightsDialog(
                                      displaySummary, displayKeywords),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (data['cbvrStatus'] == 'processing' &&
                              cbvrSummary == null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.orange),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'The AI is currently watching this video to generate a highly accurate summary. Showing temporary basic summary...',
                                      style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                          height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (hasError) ...[
                            Text(
                                displaySummary.isNotEmpty
                                    ? displaySummary
                                    : 'No AI Insight available.',
                                style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                    height: 1.5)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.greenPrime,
                                  side: const BorderSide(
                                      color: AppTheme.greenPrime),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed:
                                    _isRegeneratingAi ? null : _regenerateAi,
                                icon: _isRegeneratingAi
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.greenPrime))
                                    : const Icon(Icons.auto_awesome),
                                label: Text(_isRegeneratingAi
                                    ? 'Generating...'
                                    : 'Generate AI Insight'),
                              ),
                            ),
                          ] else ...[
                            if (displaySummary.isNotEmpty) ...[
                              InkWell(
                                onTap: () => setState(() =>
                                    _isSummaryExpanded = !_isSummaryExpanded),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text('Summary',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                    ),
                                    Icon(
                                      _isSummaryExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeInOut,
                                alignment: Alignment.topCenter,
                                child: _isSummaryExpanded
                                    ? Text(displaySummary,
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 13,
                                            height: 1.5))
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (displayKeywords.isNotEmpty) ...[
                              const Text('Keywords',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: displayKeywords.map((tag) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.greenPrime
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text('#$tag',
                                        style: const TextStyle(
                                            color: AppTheme.greenPrime,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500)),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ]);
          },
        ),
      ],
    );

    // ✅ NEW: on a wide (desktop/Chrome) window, the video header used to
    // size itself to the FULL browser width while the text/details below
    // it (title, meta tags, description...) were a separate block that
    // ALSO stretched to the full width -- the two didn't line up, and
    // together they made the page feel oversized/occupied. Now both the
    // video and the details are wrapped in one shared max-width container
    // and centered, so they share the exact same edges and the whole page
    // reads as one contained column instead of a huge stretched screen. On
    // an actual phone (narrow width) this has zero effect.
    final isWide = MediaQuery.of(context).size.width > 900;
    // ✅ NEW: on a really wide window there's enough room for the
    // Comments + Related carousel to sit BESIDE the video/details instead
    // of stacked underneath them, matching the reference mockup.
    final isTwoColumn = MediaQuery.of(context).size.width > 1100;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      // ✅ CHANGED: the back button used to float ON TOP of the video
      // thumbnail itself (a Positioned circle in the corner of the video
      // Stack) -- moved out to a real AppBar above the video instead, same
      // as every other screen in the app (Edit Documentary, the genre
      // list, etc.), so nothing overlaps the thumbnail anymore.
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // ✅ CHANGED: this used to be a flat percentage of the viewport
            // height (0.42) with no regard for how wide the video actually
            // renders -- on a normal-height desktop window that percentage
            // came out SHORTER than a proper 16:9 height for the newly
            // widened video, which forced the video to shrink narrower
            // again to keep its aspect ratio (undoing the width fix
            // above). Now the height is derived from the video's actual
            // width instead, so it always renders as a clean, proportional
            // 16:9 box at full width. The viewport percentage is now only
            // a safety ceiling for an unusually short window, not the
            // primary driver.
            // ✅ CHANGED: in two-column mode the video/details only occupy
            // the LEFT column (820px), not the full page width, since the
            // right side is now taken up by Comments + Related.
            final leftColumnWidth =
                isTwoColumn ? 820.0 : (isWide ? 900.0 : constraints.maxWidth);
            final headerWidth = leftColumnWidth - (isWide ? 32 : 0);
            final idealHeaderHeight = headerWidth * 9 / 16;
            final viewportCap = constraints.maxHeight * (isWide ? 0.7 : 0.5);
            final maxHeaderHeight = idealHeaderHeight < viewportCap
                ? idealHeaderHeight
                : viewportCap;
            // ✅ CHANGED: the video header and the Comments/Related side
            // column used to both be children of the SAME outer Column --
            // which meant the side column only started AFTER the video's
            // full height (since a Column stacks its children top to
            // bottom), leaving it floating way down the page instead of
            // starting level with the video's top like the mockup. Now the
            // video+content on the left and the Comments/Related column on
            // the right are two SIDE-BY-SIDE branches of one Row, each with
            // its own matching top gap, so both start at the same height.
            final leftColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ NEW: on a wide (desktop/Chrome) window, add a small
                // gap so the video no longer sits flush against the
                // persistent top nav bar above it.
                if (isWide) const SizedBox(height: 16),
                // ✅ NEW: the video used to be edge-to-edge across the
                // full 900px container, while the details below it
                // (including the AI Insights box) sat inside 16px of
                // padding -- 32px narrower overall, so the two never
                // lined up in width. Now the video gets that same 16px
                // horizontal padding on a wide window, so it's exactly
                // as wide as AI Insights and everything else below it.
                // Phone is untouched (still edge-to-edge, as before).
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isWide ? 12 : 0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: maxHeaderHeight,
                          maxWidth: leftColumnWidth),
                      child: _buildHeader(),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    // ✅ NEW: two-column layout leaves Comments + Related
                    // out of here entirely (they're their own column in
                    // the Row below); narrower windows keep the old single
                    // stacked column, with Comments and the new Related
                    // carousel appended after the details.
                    child: isTwoColumn
                        ? content
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              content,
                              const SizedBox(height: 24),
                              _buildCommentsCard(),
                              const SizedBox(height: 24),
                              _buildRelatedSection(),
                            ],
                          ),
                  ),
                ),
              ],
            );

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth:
                        isTwoColumn ? 1240 : (isWide ? 900 : double.infinity)),
                child: isTwoColumn
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: leftColumn),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 380,
                            child: Column(
                              children: [
                                // Same top gap as the video, so Comments
                                // starts level with the video's TOP edge
                                // instead of down near the title.
                                if (isWide) const SizedBox(height: 16),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.only(
                                        top: 16, right: 16, bottom: 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildCommentsCard(),
                                        const SizedBox(height: 24),
                                        _buildRelatedSection(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : leftColumn,
              ),
            );
          },
        ),
      ),
    );
  }

  // ✅ NEW: wraps the existing CommentSection widget in the same card
  // styling as AI Insights, per the reference mockup.
  Widget _buildCommentsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: CommentSection(filmId: widget.film.id),
    );
  }

  // ✅ NEW: "Related / More from PSAUniFilms" horizontal carousel, per the
  // reference mockup -- other films in the same genre, with left/right
  // arrow buttons. Note: the app doesn't track each video's actual
  // running time anywhere yet, so unlike the mockup these cards don't
  // show a duration badge -- happy to add that later if you start saving
  // duration when a film is uploaded.
  Widget _buildRelatedSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dashboard_rounded,
                  color: AppTheme.textPrimary, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Related / More from PSAUniFilms',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded,
                    color: AppTheme.textMuted),
                onPressed: () => _scrollRelated(-260),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted),
                onPressed: () => _scrollRelated(260),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: FutureBuilder<List<Film>>(
              future: _relatedFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.greenPrime));
                }
                final related = snapshot.data!;

                if (related.isEmpty) {
                  return const Center(
                    child: Text('No related documentaries yet.',
                        style:
                            TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  );
                }

                return ListView.separated(
                  controller: _relatedScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: related.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _relatedCard(related[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _relatedCard(Film film) {
    return GestureDetector(
      onTap: () => _openFilm(film),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: film.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        film.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF1E301E),
                          child: const Icon(Icons.movie_outlined,
                              color: AppTheme.textMuted),
                        ),
                      )
                    : Container(
                        color: const Color(0xFF1E301E),
                        child: const Icon(Icons.movie_outlined,
                            color: AppTheme.textMuted),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              film.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final hasVideo = widget.film.videoUrl.isNotEmpty;

    return Stack(
      children: [
        if (hasVideo)
          if (_checkingStatus)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.greenPrime)),
              ),
            )
          else if (_videoStatus != null && _videoStatus! < 3)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_empty,
                          color: Colors.white70, size: 40),
                      SizedBox(height: 12),
                      Text('Video is processing on the server...',
                          style: TextStyle(color: Colors.white70)),
                      Text('Please check back in a few minutes.',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            )
          else
            CustomVideoPlayer(
              key: _videoPlayerKey,
              videoUrl: widget.film.videoUrl,
              onViewStarted: _logViewStarted,
              onViewCompleted: _logViewCompleted,
            )
        else
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: AppTheme.bgCard,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.movie_outlined,
                        color: AppTheme.textMuted, size: 60),
                    SizedBox(height: 8),
                    Text(
                      'No video available',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _metaTag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
      );
}
