import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

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
  late YoutubePlayerController _controller;
  bool _showControls = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.youtubeId,
      flags: YoutubePlayerFlags(
        autoPlay: widget.autoPlay,
        mute: widget.mute,
        loop: widget.loop,
        hideControls: true,
        enableCaption: false,
        disableDragSeek: true,
      ),
    );

    _controller.addListener(_listener);

    if (!widget.disableControls && !widget.autoPlay) {
      _showControls = true;
      _startHideTimer();
    }
  }

  void _listener() {
    if (_controller.value.playerState == PlayerState.ended && widget.loop) {
      _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_listener);
    _controller.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (widget.disableControls) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _skip(int seconds) {
    final currentPosition = _controller.value.position;
    _controller.seekTo(currentPosition + Duration(seconds: seconds));
    _startHideTimer();
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      _showControls = true;
      _hideTimer?.cancel();
    } else {
      _controller.play();
      _startHideTimer();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // YoutubePlayerBuilder correctly handles fullscreen transitions without
    // destroying and recreating the underlying WebView, so the video keeps
    // playing seamlessly when entering or exiting full screen.
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: false,
        bottomActions: const [],
      ),
      builder: (context, player) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // 1. The actual player — touch blocked so native YT UI won't show
              AbsorbPointer(
                absorbing: true,
                child: player,
              ),

              // 2. Gradient at the top to hide YouTube title & channel name
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black, Colors.transparent],
                    ),
                  ),
                ),
              ),

              // 3. Small gradient in the bottom-right to hide the YouTube logo
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 72,
                  height: 36,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomRight,
                      end: Alignment.topLeft,
                      colors: [Colors.black, Colors.transparent],
                    ),
                  ),
                ),
              ),

              // 4. Tap area for toggling controls visibility
              if (!widget.disableControls)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      color: _showControls ? Colors.black54 : Colors.transparent,
                    ),
                  ),
                ),

              // 5. Center playback controls (replay 10s / play-pause / forward 10s)
              if (_showControls && !widget.disableControls)
                Positioned.fill(
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10, color: Colors.white, size: 48),
                          onPressed: () => _skip(-10),
                        ),
                        const SizedBox(width: 32),
                        ValueListenableBuilder<YoutubePlayerValue>(
                          valueListenable: _controller,
                          builder: (context, value, _) => IconButton(
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 64,
                            ),
                            onPressed: _togglePlay,
                          ),
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

              // 6. Bottom row: position / progress bar / duration / fullscreen
              if (_showControls && !widget.disableControls)
                Positioned(
                  bottom: 8,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      CurrentPosition(controller: _controller),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ProgressBar(
                          controller: _controller,
                          isExpanded: true,
                          colors: const ProgressBarColors(
                            playedColor: Color(0xFF4CAF50),
                            handleColor: Color(0xFF4CAF50),
                            bufferedColor: Colors.white54,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      RemainingDuration(controller: _controller),
                      if (widget.isFullScreenButtonVisible)
                        ValueListenableBuilder<YoutubePlayerValue>(
                          valueListenable: _controller,
                          builder: (context, value, _) => IconButton(
                            icon: Icon(
                              value.isFullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              color: Colors.white,
                            ),
                            // toggleFullScreenMode() is handled entirely by
                            // YoutubePlayerBuilder — the player WebView is
                            // never destroyed, so the video keeps playing.
                            onPressed: () => _controller.toggleFullScreenMode(),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
