import 'dart:async';
import 'package:flutter/material.dart';
import '../models/film.dart';
import 'custom_video_player.dart';

class ShowcaseBanner extends StatefulWidget {
  final List<Film> films;
  final Function(Film) onTap; // Kept for signature, but unused by tap on the banner itself.

  const ShowcaseBanner({
    super.key,
    required this.films,
    required this.onTap,
  });

  @override
  State<ShowcaseBanner> createState() => _ShowcaseBannerState();
}

class _ShowcaseBannerState extends State<ShowcaseBanner> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    if (widget.films.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.films.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(ShowcaseBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.films.length != oldWidget.films.length) {
      if (_currentIndex >= widget.films.length) {
        _currentIndex = 0;
      }
      _timer?.cancel();
      _startTimer();
    }
  }

  Film get _currentFilm => widget.films[_currentIndex];

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

    final hasVideo = _currentFilm.youtubeId != null && _currentFilm.youtubeId!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: hasVideo
            ? CustomVideoPlayer(
                key: ValueKey(_currentFilm.youtubeId),
                youtubeId: _currentFilm.youtubeId!,
                autoPlay: true,
                mute: true,
                disableControls: true,
                loop: true,
              )
            : (_currentFilm.thumbnailUrl.isNotEmpty
                ? Image.network(
                    _currentFilm.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderBox(),
                  )
                : _placeholderBox()),
      ),
    );
  }
}
