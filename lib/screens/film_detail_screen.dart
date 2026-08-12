import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/film.dart';

class FilmDetailScreen extends StatefulWidget {
  final Film film;
  const FilmDetailScreen({super.key, required this.film});
  @override
  State<FilmDetailScreen> createState() => _FilmDetailScreenState();
}

class _FilmDetailScreenState extends State<FilmDetailScreen> {
  YoutubePlayerController? _controller;
  bool _inWatchlist = false;
  bool _loadingWatchlist = true;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference get _watchlistRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('watchlist')
      .doc(widget.film.id);

  @override
  void initState() {
    super.initState();
    _initYoutube();
    _checkWatchlist();
  }

  void _initYoutube() {
    final id = widget.film.youtubeId;
    if (id == null || id.isEmpty) return;
    _controller = YoutubePlayerController(
      initialVideoId: id,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        enableCaption: true,
        forceHD: false,
      ),
    );
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
          'youtubeId': widget.film.youtubeId ?? '',
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
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller ?? YoutubePlayerController(initialVideoId: ''),
        showVideoProgressIndicator: true,
        progressIndicatorColor: AppTheme.greenPrime,
        bottomActions: const [
          CurrentPosition(),
          ProgressBar(isExpanded: true),
          RemainingDuration(),
          FullScreenButton(),
        ],
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: AppTheme.bgDark,
          body: Column(
            children: [
              _buildHeader(player),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + Rating
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
                          Row(children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.film.rating}',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Meta tags
                      Row(children: [
                        _metaTag('${widget.film.year}'),
                        const SizedBox(width: 8),
                        _metaTag(widget.film.genre),
                      ]),
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
                            foregroundColor: _inWatchlist
                                ? AppTheme.greenPrime
                                : AppTheme.textPrimary,
                            side: BorderSide(
                              color: _inWatchlist
                                  ? AppTheme.greenPrime
                                  : AppTheme.borderColor,
                            ),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed:
                              _loadingWatchlist ? null : _toggleWatchlist,
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

                      // About
                      const Text(
                        'About',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.film.description,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // AI Analysis Section
                      if (widget.film.aiSummary.isNotEmpty || widget.film.aiKeywords.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF132A1D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.greenPrime.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome, color: AppTheme.greenPrime, size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'AI Insights',
                                    style: TextStyle(
                                      color: AppTheme.greenPrime,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (widget.film.aiSummary.isNotEmpty) ...[
                                const Text(
                                  'Summary',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.film.aiSummary,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (widget.film.aiKeywords.isNotEmpty) ...[
                                const Text(
                                  'Keywords',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: widget.film.aiKeywords.map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.greenPrime.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        '#$tag',
                                        style: const TextStyle(
                                          color: AppTheme.greenPrime,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Widget player) {
    if (_controller == null) {
      return Stack(
        children: [
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
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        player,
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.pop(context),
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
