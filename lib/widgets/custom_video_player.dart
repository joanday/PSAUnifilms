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
  }) : assert(videoUrl != null || videoFile != null, 'Either videoUrl or videoFile must be provided');

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
        _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!));
      }
      await _videoPlayerController.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: widget.autoPlay,
        looping: widget.loop,
        showControls: !widget.disableControls,
        allowFullScreen: true,
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

    if (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Chewie(
          controller: _chewieController!,
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
