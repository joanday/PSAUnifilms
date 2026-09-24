import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class CustomVideoPlayer extends StatefulWidget {
  final String? videoUrl;
  final File? videoFile;
  final bool autoPlay;
  final bool mute;
  final bool isFullScreenButtonVisible;
  final VoidCallback? onFullScreenPressed;
  final bool disableControls;
  final bool loop;
  // ✅ NEW: optional hooks for usage-analytics logging. onViewStarted fires
  // once per playback session, the first time the video has played a
  // couple of seconds (so an accidental tap that's immediately closed
  // doesn't count as a "view"). onViewCompleted fires once, when playback
  // reaches (or nearly reaches) the end. This widget stays fully generic
  // and doesn't know or care WHAT its caller does with these -- the caller
  // (film_detail_screen.dart) is the one that actually writes to
  // Firestore.
  final VoidCallback? onViewStarted;
  final VoidCallback? onViewCompleted;

  const CustomVideoPlayer({
    super.key,
    this.videoUrl,
    this.videoFile,
    this.autoPlay = false,
    this.mute = false,
    this.isFullScreenButtonVisible = false,
    this.onFullScreenPressed,
    this.disableControls = false,
    this.loop = false,
    this.onViewStarted,
    this.onViewCompleted,
  }) : assert(videoUrl != null || videoFile != null,
            'Either videoUrl or videoFile must be provided');

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  // ✅ CHANGED (real fix this time): the earlier fix only stopped there
  // from being TWO Chewie widgets mounted at once, but the video was
  // still stopping because opening/closing fullscreen still DESTROYED the
  // small player's Chewie widget and CREATED a brand new one for the
  // fullscreen page (and again on the way back). On Flutter Web, that
  // also tears down and rebuilds the underlying HTML <video> element,
  // which is what was actually causing the stop -- not just two players
  // competing.
  //
  // The real fix: build the Chewie widget ONCE, tagged with _playerKey,
  // and reuse that exact same widget (same GlobalKey) whether it's
  // showing inline (small player) or inside the fullscreen overlay below.
  // When a widget with a GlobalKey moves to a different spot in the tree
  // within the same frame, Flutter MOVES its existing Element (and the
  // real video element under it) instead of destroying and recreating
  // it -- so playback is never interrupted either way.
  final GlobalKey _playerKey = GlobalKey();
  OverlayEntry? _fullScreenEntry;
  bool _isFullScreenOpen = false;
  // ✅ NEW: guards so onViewStarted/onViewCompleted each fire at most once
  // per playback session, no matter how much the position listener ticks.
  bool _startCounted = false;
  bool _completeCounted = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  // ✅ NEW: watches playback position to detect a "real" view (played past
  // ~2 seconds) and a "completed" view (reached, or nearly reached, the
  // end). Uses position vs. duration rather than a fixed time for
  // completion so it works for videos of any length.
  void _onVideoProgress() {
    if (!mounted) return;
    final value = _videoPlayerController.value;
    if (!value.isInitialized || value.duration == Duration.zero) return;

    if (!_startCounted &&
        (value.position.inMilliseconds >= 2000 ||
            value.position >= value.duration)) {
      _startCounted = true;
      widget.onViewStarted?.call();
    }

    if (!_completeCounted &&
        value.position.inMilliseconds >= value.duration.inMilliseconds - 1500) {
      _completeCounted = true;
      widget.onViewCompleted?.call();
    }
  }

  Future<void> _initializePlayer() async {
    try {
      if (widget.videoFile != null) {
        _videoPlayerController = VideoPlayerController.file(widget.videoFile!);
      } else {
        VideoFormat? formatHint;
        String finalUrl = widget.videoUrl!;

        // Ensure HLS format is explicitly hinted for Bunny.net adaptive streams
        // to prevent ExoPlayer from failing during chunk transitions.
        if (finalUrl.toLowerCase().contains('.m3u8')) {
          formatHint = VideoFormat.hls;
        }

        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(finalUrl),
          formatHint: formatHint,
          videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: true, allowBackgroundPlayback: false),
        );
      }
      await _videoPlayerController.initialize();
      _videoPlayerController.addListener(_onVideoProgress);

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: widget.autoPlay,
        looping: widget.loop,
        showControls: !widget.disableControls,
        // Chewie's built-in fullscreen locks device orientation, which is a
        // no-op on Flutter Web and leaves its internal layout permanently
        // mismatched (causes a RenderFlex overflow). We disable it here and
        // provide our own web-safe fullscreen toggle below instead.
        allowFullScreen: false,
        fullScreenByDefault: false,
        // ✅ CHANGED: this is meant to turn off Chewie's own built-in
        // settings/options gear icon (it used to sit bottom-right of the
        // control bar, overlapping our own Fullscreen button there). Just
        // setting allowPlaybackSpeedChanging to false was NOT enough --
        // Chewie's desktop/web control bar still draws that gear icon
        // regardless, since the icon itself is controlled separately from
        // which options appear inside it. showOptions: false is the flag
        // that actually removes the icon from the control bar entirely.
        // Our own Settings icon (top-right, see _openSettingsMenu below)
        // takes over that job instead, so the two no longer overlap.
        allowPlaybackSpeedChanging: false,
        showOptions: false,
        aspectRatio: 16 / 9,
        autoInitialize: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );

      if (widget.mute) {
        _videoPlayerController.setVolume(0);
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      setState(() {
        _isError = true;
      });
    }
  }

  // Builds the ONE Chewie widget instance (see _playerKey note above) --
  // both the inline small player and the fullscreen overlay call this
  // exact same method, so it's always the same widget, just relocated.
  Widget _buildPlayerCore() {
    return Chewie(key: _playerKey, controller: _chewieController!);
  }

  // ✅ CHANGED: fullscreen no longer pushes a new page/route at all -- it
  // inserts an OverlayEntry on top of everything instead, and reuses
  // _buildPlayerCore() (same GlobalKey) inside it. See the note on
  // _playerKey above for why this is what actually stops playback from
  // interrupting on open/close.
  void _openFullScreen() {
    if (_chewieController == null || _isFullScreenOpen) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _fullScreenEntry = OverlayEntry(
      builder: (_) => _FullScreenOverlayPlayer(
        aspectRatio: _videoPlayerController.value.aspectRatio,
        player: _buildPlayerCore(),
        onClose: _closeFullScreen,
      ),
    );
    overlay.insert(_fullScreenEntry!);
    setState(() => _isFullScreenOpen = true);
  }

  void _closeFullScreen() {
    _fullScreenEntry?.remove();
    _fullScreenEntry = null;
    if (mounted) {
      setState(() => _isFullScreenOpen = false);
    }
  }

  // ✅ NEW: our own lightweight "Settings" menu (playback speed) -- takes
  // over the job Chewie's built-in options/gear icon used to do, now that
  // that icon is switched off above (allowPlaybackSpeedChanging: false).
  void _openSettingsMenu() {
    if (_chewieController == null) return;
    final controller = _chewieController!.videoPlayerController;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16241A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Playback Speed',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              for (final speed in speeds)
                ListTile(
                  title: Text('${speed}x',
                      style: const TextStyle(color: Colors.white)),
                  trailing: controller.value.playbackSpeed == speed
                      ? const Icon(Icons.check, color: Color(0xFF4CAF50))
                      : null,
                  onTap: () {
                    controller.setPlaybackSpeed(speed);
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _fullScreenEntry?.remove();
    _videoPlayerController.removeListener(_onVideoProgress);
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.error_outline, color: Colors.white),
          ),
        ),
      );
    }

    if (_chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // While the fullscreen overlay is open, the real player widget
            // has been relocated there (same GlobalKey -- see the note on
            // _playerKey above), so this spot just shows a plain black
            // placeholder instead of a second one.
            _isFullScreenOpen
                ? Container(color: Colors.black)
                : _buildPlayerCore(),
            // ✅ CHANGED: per feedback, swapped these two icons' spots --
            // Settings is now up top-right (where Fullscreen used to be)
            // and Fullscreen is now bottom-right (where Chewie's own
            // built-in settings/options gear used to be). That native gear
            // is switched off above (allowPlaybackSpeedChanging: false),
            // so nothing else competes for the bottom-right corner anymore.
            if (!widget.disableControls) ...[
              Positioned(
                right: 8,
                top: 8,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.settings,
                        color: Colors.white, size: 22),
                    tooltip: 'Settings',
                    onPressed: _openSettingsMenu,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen,
                        color: Colors.white, size: 24),
                    tooltip: 'Fullscreen',
                    onPressed: _openFullScreen,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Loading state
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// A plain full-screen overlay for the video -- no device orientation
/// locking, so it works correctly on Flutter Web as well as mobile. Unlike
/// a pushed page/route, this never creates its own new Chewie widget --
/// `player` (built by _buildPlayerCore() above) is the SAME widget
/// instance/GlobalKey that was showing inline a moment ago, just relocated
/// here, so the video itself is never torn down or rebuilt.
class _FullScreenOverlayPlayer extends StatelessWidget {
  final double aspectRatio;
  final Widget player;
  final VoidCallback onClose;

  const _FullScreenOverlayPlayer({
    required this.aspectRatio,
    required this.player,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
                child: player,
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Exit fullscreen',
                  onPressed: onClose,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
