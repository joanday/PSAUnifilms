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
  }) : assert(videoUrl != null || videoFile != null,
            'Either videoUrl or videoFile must be provided');

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
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

  void _openFullScreen() {
    if (_chewieController == null) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _FullScreenPlayerPage(
          chewieController: _chewieController!,
        ),
      ),
    );
  }

  @override
  void dispose() {
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
            Chewie(controller: _chewieController!),
            if (!widget.disableControls)
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.transparent,
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen,
                        color: Colors.white, size: 28),
                    tooltip: 'Fullscreen',
                    onPressed: _openFullScreen,
                  ),
                ),
              ),
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

/// A plain full-screen page for the video -- no device orientation locking,
/// so it works correctly on Flutter Web as well as mobile.
class _FullScreenPlayerPage extends StatelessWidget {
  final ChewieController chewieController;

  const _FullScreenPlayerPage({required this.chewieController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio:
                    chewieController.videoPlayerController.value.aspectRatio,
                child: Chewie(controller: chewieController),
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
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
