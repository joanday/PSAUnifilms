import 'package:flutter/material.dart';
import '../widgets/custom_video_player.dart';

class WatchScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String description;

  const WatchScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    required this.description,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  String _videoQuality = 'HD (720p)';
  String _subtitleLanguage = 'Filipino';

  static const _greenPrime = Color(0xFF4CAF50);
  static const _bgCard = Color(0xFF16241C);
  static const _textMuted = Colors.white60;

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
                    // ignore: deprecated_member_use
                    groupValue: _videoQuality,
                    activeColor: _greenPrime,
                    title: Text(q,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    // ignore: deprecated_member_use
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
                    // ignore: deprecated_member_use
                    groupValue: _subtitleLanguage,
                    activeColor: _greenPrime,
                    title: Text(l,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    // ignore: deprecated_member_use
                    onChanged: (v) {
                      setState(() => _subtitleLanguage = v!);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          // Custom Clean Native Video Player
          CustomVideoPlayer(
            videoUrl: widget.videoUrl,
            autoPlay: true,
          ),

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
  }
}
