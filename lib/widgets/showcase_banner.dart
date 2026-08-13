import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/film.dart';

class ShowcaseBanner extends StatefulWidget {
  final List<Film> films;
  final Function(Film) onTap;

  const ShowcaseBanner({
    super.key,
    required this.films,
    required this.onTap,
  });

  @override
  State<ShowcaseBanner> createState() => _ShowcaseBannerState();
}

class _ShowcaseBannerState extends State<ShowcaseBanner> {
  YoutubePlayerController? _controller;
  bool _isPlayerReady = false;
  int _currentIndex = 0;
  Timer? _timer;

  Film get _currentFilm => widget.films[_currentIndex];

  @override
  void initState() {
    super.initState();
    if (widget.films.isNotEmpty) {
      _initController();
    }
  }

  void _initController() {
    if (_currentFilm.youtubeId == null || _currentFilm.youtubeId!.isEmpty) return;
    
    _controller = YoutubePlayerController(
      initialVideoId: _currentFilm.youtubeId!,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true,
        hideControls: true,
        loop: true,
        disableDragSeek: true,
        isLive: false,
        forceHD: false,
        startAt: 10,
        endAt: 16, // 6-second chunk per load
      ),
    );
  }

  void _startCycling() {
    if (widget.films.length <= 1) return;
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted) return;
      
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.films.length;
        _isPlayerReady = false; // Reset ready state for overlay transition
      });
      
      if (_currentFilm.youtubeId != null && _currentFilm.youtubeId!.isNotEmpty) {
        _controller?.load(_currentFilm.youtubeId!, startAt: 10);
      }
    });
  }

  @override
  void didUpdateWidget(ShowcaseBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.films != widget.films) {
      _timer?.cancel();
      _controller?.dispose();
      _controller = null; // Prevent using disposed controller
      _currentIndex = 0;
      if (widget.films.isNotEmpty) {
        _initController();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  Widget _placeholderBox() {
    return Container(
      height: 200,
      width: double.infinity,
      color: const Color(0xFF1A3528),
      child: const Center(
        child: Icon(Icons.movie, color: Colors.white24, size: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.films.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => widget.onTap(_currentFilm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Video Player or Fallback Thumbnail
            SizedBox(
              height: 200,
              width: double.infinity,
              child: _controller != null
                  ? AbsorbPointer(
                      child: YoutubePlayer(
                        controller: _controller!,
                        showVideoProgressIndicator: false,
                        onReady: () {
                          if (mounted) {
                            setState(() => _isPlayerReady = true);
                            if (_timer == null) {
                              _startCycling();
                            }
                          }
                        },
                      ),
                    )
                  : (_currentFilm.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          _currentFilm.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderBox(),
                        )
                      : _placeholderBox()),
            ),
            
            // Top Gradient Overlay (Hides YouTube Title/Uploader text)
            Container(
              height: 70,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0D1F17).withOpacity(0.95),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            
            // Gradient Overlay for readability
            Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0D1F17).withOpacity(0.8),
                    const Color(0xFF0D1F17),
                  ],
                  stops: const [0.4, 0.8, 1.0],
                ),
              ),
            ),

            // Text content layered on top
            Positioned(
              left: 16,
              bottom: 16,
              right: 16,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Column(
                  key: ValueKey<String>(_currentFilm.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'MONTHLY SHOWCASE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentFilm.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentFilm.genre,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Play Button Icon Overlay (Netflix style)
            if (_isPlayerReady)
              Positioned(
                right: 16,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
