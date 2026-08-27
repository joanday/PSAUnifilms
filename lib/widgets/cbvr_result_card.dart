import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/film.dart';
import '../services/cbvr_service.dart';

/// A film card specifically designed for CBVR search results.
///
/// Shows the film thumbnail, title, year/genre, a color-coded relevance
/// score badge, and a short AI-generated match reason.
class CbvrResultCard extends StatefulWidget {
  final Film film;
  final CbvrResult result;
  final VoidCallback onTap;
  final int animationIndex;

  const CbvrResultCard({
    super.key,
    required this.film,
    required this.result,
    required this.onTap,
    this.animationIndex = 0,
  });

  @override
  State<CbvrResultCard> createState() => _CbvrResultCardState();
}

class _CbvrResultCardState extends State<CbvrResultCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Stagger entry animation based on card index.
    Future.delayed(
      Duration(milliseconds: widget.animationIndex * 80),
      () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF4CAF50); // green
    if (score >= 55) return const Color(0xFFFFB300); // amber
    return const Color(0xFFEF5350); // red-ish (low relevance)
  }

  String _scoreLabel(int score) {
    if (score >= 80) return 'Strong Match';
    if (score >= 55) return 'Good Match';
    return 'Partial Match';
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(widget.result.score);

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2E22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scoreColor.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(13),
                    bottomLeft: Radius.circular(13),
                  ),
                  child: widget.film.thumbnailUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.film.thumbnailUrl,
                          width: 100,
                          height: 80,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),

                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          widget.film.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Year · Genre
                        Text(
                          '${widget.film.year} · ${widget.film.genre}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // AI reason chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1F17),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF2A4535),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF4CAF50),
                                size: 10,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  widget.result.reason,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Score badge
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Circular score
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: widget.result.score / 100,
                              backgroundColor:
                                  scoreColor.withValues(alpha: 0.15),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(scoreColor),
                              strokeWidth: 3.5,
                            ),
                            Center(
                              child: Text(
                                '${widget.result.score}%',
                                style: TextStyle(
                                  color: scoreColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _scoreLabel(widget.result.score),
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 100,
        height: 80,
        color: const Color(0xFF0D1F17),
        child:
            const Icon(Icons.movie_outlined, color: Colors.white24, size: 28),
      );
}
