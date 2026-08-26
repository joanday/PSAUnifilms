import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../services/fcm_token_service.dart';
import '../services/ai_service.dart';

class SubmitFilmScreen extends StatefulWidget {
  const SubmitFilmScreen({super.key});

  @override
  State<SubmitFilmScreen> createState() => _SubmitFilmScreenState();
}

class _SubmitFilmScreenState extends State<SubmitFilmScreen> {
  final titleController = TextEditingController();
  final directorController = TextEditingController();
  final descController = TextEditingController();
  final urlController = TextEditingController();
  bool isLoading = false;
  String loadingText = '';
  int loadingPercentage = 0;
  Timer? _progressTimer;
  String? errorMessage;
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
  void initState() {
    super.initState();
    _testToken();
  }

  Future<void> _testToken() async {
    try {
      final token = await getAccessToken();
      print('Access token: $token');
    } catch (e) {
      print('Error getting token: $e');
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

  Future<void> _uploadFilm() async {
    if (titleController.text.trim().isEmpty ||
        directorController.text.trim().isEmpty ||
        urlController.text.trim().isEmpty) {
      setState(() => errorMessage = 'Please fill in all required fields.');
      return;
    }

    final uri = Uri.tryParse(urlController.text.trim());
    final youtubeId = uri?.queryParameters['v'];

    if (youtubeId == null || youtubeId.isEmpty) {
      setState(() =>
          errorMessage = 'Invalid YouTube URL. Make sure it contains ?v=');
      return;
    }

    if (_selectedGenre == null) {
      setState(() => errorMessage = 'Please select a theme/genre.');
      return;
    }

    setState(() {
      isLoading = true;
      loadingText = 'Preparing upload...';
      loadingPercentage = 0;
      errorMessage = null;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (mounted && loadingPercentage < 95) {
        setState(() {
          loadingPercentage++;
        });
      }
    });

    try {
      // Since Firebase Storage is disabled, we rely solely on YouTube thumbnails.
      String thumbnailUrl = 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';

      setState(() {
        loadingText = 'Generating AI Metadata...';
      });

      String aiSummary = '';
      List<String> aiKeywords = [];

      try {
        final aiData = await AiService.generateMetadata(
          titleController.text.trim(),
          descController.text.trim(),
          youtubeId: youtubeId,
        );
        aiSummary = aiData.summary;
        aiKeywords = aiData.keywords;
      } catch (aiError) {
        aiSummary = 'AI Generation Failed: $aiError. Tap to retry.';
      }

      _progressTimer?.cancel();
      setState(() {
        loadingPercentage = 100;
        loadingText = 'Submitting to database...';
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;

      await FirebaseFirestore.instance.collection('films').add({
        'title': titleController.text.trim(),
        'director': directorController.text.trim(),
        'description': descController.text.trim(),
        'genre': _selectedGenre,
        'year': DateTime.now().year,
        'youtubeId': youtubeId,
        'thumbnail': thumbnailUrl,
        'uploadedBy': uid,
        'uploaderName': FirebaseAuth.instance.currentUser?.email?.split('@')[0],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'aiSummary': aiSummary,
        'aiKeywords': aiKeywords,
        'isOldDocumentary': !_isNewDocumentary,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Film submitted! Waiting for approval.'),
            backgroundColor: Color(0xFF2E7D52),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => errorMessage = 'Submission failed: $e');
      }
    } finally {
      _progressTimer?.cancel();
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    directorController.dispose();
    descController.dispose();
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F17),
        elevation: 0,
        title: const Text(
          'Submit Film',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Film Details',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Fill in the details of the film you want to submit.',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 24),

            // Title
            const Text('Title', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. The Last Forest',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A3528),
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

            // Director
            const Text('Director', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: directorController,
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

            // Description
            const Text('Description (Optional)', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: descController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Leave blank to let AI Insight generate it automatically...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A3528),
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

            // YouTube URL
            const Text('YouTube URL', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://youtube.com/watch?v=...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A3528),
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
                prefixIcon: const Icon(Icons.link, color: Colors.white38),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tip: Upload your film to YouTube first, then paste the link here.',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 16),


            // Error message
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(errorMessage!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D52),
                  disabledBackgroundColor:
                      const Color(0xFF2E7D52).withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed:
                    isLoading ? null : _uploadFilm,
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.upload_rounded, color: Colors.white),
                label: Text(
                  isLoading ? '$loadingText $loadingPercentage%' : 'Submit Film',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
