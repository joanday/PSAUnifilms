import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/film.dart';
import '../widgets/custom_video_player.dart';
import '../services/ai_service.dart';
import '../services/bunny_service.dart';
import '../widgets/comment_section.dart';

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
        await _watchlistRef.set({
          'filmId': widget.film.id,
          'title': widget.film.title,
          'genre': widget.film.genre,
          'year': widget.film.year,
          'rating': widget.film.rating,
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

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
        Row(
          children: [
            _metaTag('${widget.film.year}'),
            const SizedBox(width: 8),
            _metaTag(widget.film.genre),
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
                  'Directed by ${widget.film.director}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

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
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
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
                  CommentSection(filmId: widget.film.id),
                ]);
          },
        ),
        const SizedBox(height: 24),
      ],
    );

    if (isLandscape) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildHeader(isLandscape),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(isLandscape),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isLandscape) {
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
        Positioned(
          top: isLandscape ? 16 : 8,
          left: isLandscape ? 24 : 8,
          child: SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                onPressed: () {
                  if (isLandscape) {
                    SystemChrome.setPreferredOrientations(
                        [DeviceOrientation.portraitUp]);
                  } else {
                    Navigator.pop(context);
                  }
                },
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
