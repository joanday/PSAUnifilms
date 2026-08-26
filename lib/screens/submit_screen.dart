import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/custom_video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' show YoutubePlayer;
import '../services/ai_service.dart';

class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  final _titleController = TextEditingController();
  final _directorController = TextEditingController();
  final _descController = TextEditingController();
  final _youtubeLinkController = TextEditingController();
  bool _isLoading = false;
  String _loadingText = '';
  int _loadingPercentage = 0;
  Timer? _progressTimer;
  String? _previewId;
  File? _coverPhoto;
  bool _isNewDocumentary = true;

  String? _selectedGenre;
  final List<String> _genres = [
    'Agriculture',
    'Culture',
    'Environment',
    'Education',
    'Community'
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _directorController.dispose();
    _descController.dispose();
    _youtubeLinkController.dispose();
    super.dispose();
  }

  void _previewVideo() {
    final id = YoutubePlayer.convertUrlToId(
      _youtubeLinkController.text.trim(),
    );
    setState(() => _previewId = id);

    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Invalid YouTube link. Please try again.')),
      );
    }
  }

  Future<void> _pickCoverPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _coverPhoto = File(result.files.single.path!);
      });
    }
  }

  void _resetForm() {
    _titleController.clear();
    _directorController.clear();
    _descController.clear();
    _youtubeLinkController.clear();
    setState(() {
      _previewId = null;
      _selectedGenre = null;
      _coverPhoto = null;
    });
  }

  Future<void> _submitFilm() async {
    final title = _titleController.text.trim();
    final director = _directorController.text.trim();
    final desc = _descController.text.trim();
    final youtubeId = YoutubePlayer.convertUrlToId(
      _youtubeLinkController.text.trim(),
    );

    // Description is now optional
    if (title.isEmpty || director.isEmpty || youtubeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields (Title, Director, YouTube URL).'),
        ),
      );
      return;
    }

    if (_selectedGenre == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a theme/genre.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingText = 'Preparing upload...';
      _loadingPercentage = 0;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (mounted && _loadingPercentage < 95) {
        setState(() {
          _loadingPercentage++;
        });
      }
    });

    try {
      // Since Firebase Storage is disabled, we rely solely on YouTube thumbnails.
      String thumbnailUrl = 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';

      setState(() {
        _loadingText = 'Generating AI Metadata...';
      });

      String aiSummary = '';
      List<String> aiKeywords = [];

      try {
        final aiData = await AiService.generateMetadata(
          title,
          desc,
          youtubeId: youtubeId,
        );
        aiSummary = aiData.summary;
        aiKeywords = aiData.keywords;
      } catch (aiError) {
        aiSummary = 'AI Generation Failed: $aiError. Tap to retry.';
      }

      _progressTimer?.cancel();
      setState(() {
        _loadingPercentage = 100;
        _loadingText = 'Submitting to database...';
      });

      await FirebaseFirestore.instance.collection('films').add({
        'title': title,
        'director': director,
        'description': desc,
        'genre': _selectedGenre,
        'year': DateTime.now().year,
        'youtubeId': youtubeId,
        'thumbnail': thumbnailUrl,
        'uploadedBy': FirebaseAuth.instance.currentUser?.uid,
        'uploaderName': FirebaseAuth.instance.currentUser?.email?.split('@')[0],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'aiSummary': aiSummary,
        'aiKeywords': aiKeywords,
        'isOldDocumentary': !_isNewDocumentary,
      });

      if (mounted) {
        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Film submitted! Waiting for approval.'),
            backgroundColor: Color(0xFF2E7D52),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _progressTimer?.cancel();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      appBar: AppBar(
        title: const Text(
          'Submit Film',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFF0D1F17),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Field
            const Text('Title', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. The Last Forest',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A3528),
                prefixIcon: const Icon(Icons.movie, color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Director Field
            const Text('Director', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: _directorController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Juan Dela Cruz',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A3528),
                prefixIcon: const Icon(Icons.person, color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Description Field
            const Text('Description (Optional)', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Leave blank to let AI Insight generate it automatically...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A3528),
                prefixIcon:
                    const Icon(Icons.description, color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Theme/Genre Dropdown
            const Text('Theme', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedGenre,
              hint: const Text('Select a Theme', style: TextStyle(color: Colors.white38)),
              dropdownColor: const Color(0xFF1A3528),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1A3528),
                prefixIcon: const Icon(Icons.category, color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                ),
              ),
              items: _genres.map((g) {
                return DropdownMenuItem(
                  value: g,
                  child: Text(g),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedGenre = val);
              },
            ),
            const SizedBox(height: 16),

            // Documentary Age Type
            const Text('Documentary Type', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    value: true,
                    groupValue: _isNewDocumentary,
                    title: const Text('New Documentary', style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF4CAF50),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _isNewDocumentary = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    value: false,
                    groupValue: _isNewDocumentary,
                    title: const Text('Old Documentary', style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF4CAF50),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _isNewDocumentary = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // YouTube Link Field
            const Text('YouTube URL', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: _youtubeLinkController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A3528),
                prefixIcon: const Icon(Icons.link, color: Colors.white38),
                suffixIcon: TextButton(
                  onPressed: _previewVideo,
                  child: const Text('Preview',
                      style: TextStyle(color: Color(0xFF4CAF50))),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E5C3E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Video Preview
            if (_previewId != null) ...[
              const Text('Preview:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white)),
              const SizedBox(height: 8),
              CustomVideoPlayer(
                youtubeId: _previewId!,
                autoPlay: false,
              ),
              const SizedBox(height: 16),
            ],

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitFilm,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload),
                label: Text(_isLoading ? '$_loadingText $_loadingPercentage%' : 'Submit Film'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D52),
                  disabledBackgroundColor:
                      const Color(0xFF2E7D52).withOpacity(0.6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
