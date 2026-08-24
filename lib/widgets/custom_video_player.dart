import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'dart:async';

class CustomVideoPlayer extends StatefulWidget {
  final String youtubeId;
  final bool autoPlay;
  final bool mute;
  final bool isFullScreenButtonVisible;
  final VoidCallback? onFullScreenPressed;
  final bool disableControls;
  final bool loop;

  const CustomVideoPlayer({
    super.key,
    required this.youtubeId,
    this.autoPlay = false,
    this.mute = false,
    this.isFullScreenButtonVisible = false,
    this.onFullScreenPressed,
    this.disableControls = false,
    this.loop = false,
  });

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final yt = YoutubeExplode();
      final manifest = await yt.videos.streamsClient.getManifest(widget.youtubeId);
      final streamInfo = manifest.muxed.withHighestBitrate();
      yt.close();

      _controller = VideoPlayerController.networkUrl(streamInfo.url);
      await _controller!.initialize();

      if (widget.mute) {
        _controller!.setVolume(0);
      }
      
      if (widget.loop) {
        _controller!.setLooping(true);
      }
      
      _controller!.addListener(() {
        if (mounted) setState(() {});
      });

      if (widget.autoPlay) {
        _controller!.play();
        _showControls = false;
      } else {
        _startHideTimer();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load video.';
        });
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _skip(int seconds) {
    if (_controller == null) return;
    final currentPosition = _controller!.value.position;
    final targetPosition = currentPosition + Duration(seconds: seconds);
    _controller!.seekTo(targetPosition);
    _startHideTimer();
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _showControls = true;
      _hideTimer?.cancel();
    } else {
      _controller!.play();
      _startHideTimer();
    }
    setState(() {});
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${duration.inHours}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
          ),
        ),
      );
    }
    if (_errorMessage != null || _controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: Center(
            child: Text(_errorMessage ?? 'Error', style: const TextStyle(color: Colors.white)),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: _buildPlayerUI(),
    );
  }

  Widget _buildPlayerUI({bool isFullScreen = false}) {
    return GestureDetector(
      onTap: widget.disableControls
          ? null
          : () {
              setState(() {
                _showControls = !_showControls;
              });
              if (_showControls) {
                _startHideTimer();
              }
            },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller!),
          if (_showControls && !widget.disableControls)
            Container(
              color: Colors.black54,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white, size: 48),
                      onPressed: () => _skip(-10),
                    ),
                    const SizedBox(width: 32),
                    IconButton(
                      icon: Icon(
                        _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white,
                        size: 64,
                      ),
                      onPressed: _togglePlay,
                    ),
                    const SizedBox(width: 32),
                    IconButton(
                      icon: const Icon(Icons.forward_10, color: Colors.white, size: 48),
                      onPressed: () => _skip(10),
                    ),
                  ],
                ),
              ),
            ),
          if (_showControls && !widget.disableControls)
            Positioned(
              bottom: 8,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Text(
                    _formatDuration(_controller!.value.position),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF4CAF50),
                        bufferedColor: Colors.white54,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDuration(_controller!.value.duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  if (widget.isFullScreenButtonVisible) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: isFullScreen
                          ? () => Navigator.of(context).pop()
                          : (widget.onFullScreenPressed ?? _enterFullScreen),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _enterFullScreen() async {
    // Force landscape mode for full screen
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (BuildContext context, _, __) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  // Rebuild the UI using the existing state
                  child: StatefulBuilder(
                    builder: (context, setInnerState) {
                      // We need to sync the inner state with the outer controller
                      _controller!.addListener(() {
                        if (mounted) setInnerState(() {});
                      });
                      return _buildPlayerUI(isFullScreen: true);
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    // Restore portrait mode when exiting full screen
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
}
