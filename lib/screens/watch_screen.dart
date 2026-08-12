import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class WatchScreen extends StatefulWidget {
  final String youtubeId;
  final String title;
  final String description;

  const WatchScreen({
    super.key,
    required this.youtubeId,
    required this.title,
    required this.description,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late YoutubePlayerController _controller;

  // Moved here from profile_screen.dart so quality/subtitle preferences are
  // reachable directly from the player instead of buried in Profile &
  // Settings. Note: youtube_player_flutter doesn't expose a real API to
  // force YouTube's actual playback bitrate, so "Video Quality" here is a
  // stored preference only, same as it was on the Profile screen before —
  // it isn't wired into YouTube's actual stream selection.
  String _videoQuality = 'HD (720p)';
  String _subtitleLanguage = 'Filipino';

  static const _greenPrime = Color(0xFF4CAF50);
  static const _bgCard = Color(0xFF16241C);
  static const _textMuted = Colors.white60;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.youtubeId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showPlaybackSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.high_quality_outlined,
                  color: Colors.white70),
              title: const Text('Video Quality',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(_videoQuality,
                  style: const TextStyle(color: _textMuted, fontSize: 12)),
              trailing:
                  const Icon(Icons.chevron_right, color: _textMuted, size: 20),
              onTap: () {
                Navigator.pop(context);
                _showVideoQualityDialog();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.subtitles_outlined, color: Colors.white70),
              title: const Text('Subtitles',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(_subtitleLanguage,
                  style: const TextStyle(color: _textMuted, fontSize: 12)),
              trailing:
                  const Icon(Icons.chevron_right, color: _textMuted, size: 20),
              onTap: () {
                Navigator.pop(context);
                _showSubtitleDialog();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showVideoQualityDialog() {
    final qualities = [
      'Low (360p)',
      'Medium (480p)',
      'HD (720p)',
      'Full HD (1080p)',
    ];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgCard,
        title:
            const Text('Video Quality', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: qualities
              .map((q) => RadioListTile<String>(
                    value: q,
                    groupValue: _videoQuality,
                    activeColor: _greenPrime,
                    title: Text(q,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    onChanged: (v) {
                      setState(() => _videoQuality = v!);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showSubtitleDialog() {
    final languages = ['Off', 'English', 'Filipino', 'Cebuano', 'Ilocano'];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgCard,
        title: const Text('Subtitles', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: languages
              .map((l) => RadioListTile<String>(
                    value: l,
                    groupValue: _subtitleLanguage,
                    activeColor: _greenPrime,
                    title: Text(l,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    onChanged: (v) {
                      setState(() => _subtitleLanguage = v!);
                      Navigator.pop(context);
                      // TODO: wire this into the YouTube player's caption
                      // track once you decide how captions are sourced
                      // (YouTube's own tracks vs. your own subtitle files).
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Colors.deepPurple,
        bottomActions: const [
          CurrentPosition(),
          ProgressBar(isExpanded: true),
          RemainingDuration(),
          FullScreenButton(),
        ],
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Playback settings',
                onPressed: _showPlaybackSettings,
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Video Player
              player,

              // Film Details
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'Description',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.description,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
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
}
