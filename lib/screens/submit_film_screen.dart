import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/fcm_token_service.dart';
import '../widgets/custom_video_player.dart';
import '../services/ai_service.dart';
import '../services/bunny_service.dart';

class SubmitFilmScreen extends StatefulWidget {
  const SubmitFilmScreen({super.key});

  @override
  State<SubmitFilmScreen> createState() => _SubmitFilmScreenState();
}

class _SubmitFilmScreenState extends State<SubmitFilmScreen> {
  final titleController = TextEditingController();
  final directorController = TextEditingController();
  final descController = TextEditingController();

  PlatformFile? _selectedVideoFile;
  PlatformFile? _selectedCoverPhoto;

  bool isLoading = false;
  String loadingText = '';
  int loadingPercentage = 0;
  Timer? _progressTimer;
  String? errorMessage;
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
      debugPrint('Access token: $token');
    } catch (e) {
      debugPrint('Error getting token: $e');
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedVideoFile = result.files.first;
      });
    }
  }

  Future<void> _pickCoverPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedCoverPhoto = result.files.first;
      });
    }
  }

  Future<void> _uploadFilm() async {
    if (titleController.text.trim().isEmpty ||
        directorController.text.trim().isEmpty ||
        _selectedVideoFile == null) {
      setState(() => errorMessage = 'Please fill in all required fields (including Video File).');
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

    try {
      final title = titleController.text.trim();
      final desc = descController.text.trim();

      // 1. Create Video Object in Bunny Stream
      setState(() => loadingText = 'Creating video in Bunny.net...');
      final guid = await BunnyService.createVideoObject(title);

      // 2. Upload Video Bytes using TUS Resumable Upload
      setState(() => loadingText = 'Uploading video file...');
      await BunnyService.uploadVideo(
        guid, 
        _selectedVideoFile!,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              loadingPercentage = progress.toInt();
            });
          }
        },
      );

      // 3. Construct URLs and Upload Cover Photo (if selected)
      final videoUrl = BunnyService.getDirectPlayUrl(guid);
      String thumbnailUrl = BunnyService.getThumbnailUrl(guid);

      if (_selectedCoverPhoto != null && _selectedCoverPhoto!.path != null) {
        setState(() => loadingText = 'Uploading cover photo to Bunny.net...');
        final coverFile = File(_selectedCoverPhoto!.path!);
        if (!await coverFile.exists()) {
          throw Exception("Selected cover photo file does not exist on device.");
        }
        
        await BunnyService.uploadThumbnail(guid, coverFile);
      }

      setState(() {
        loadingText = 'Generating AI Metadata...';
      });

      String aiSummary = '';
      List<String> aiKeywords = [];

      try {
        final aiData = await AiService.generateMetadata(title, desc);
        aiSummary = aiData.summary;
        aiKeywords = aiData.keywords;
      } catch (aiError) {
        aiSummary = 'AI Generation Failed: $aiError. Tap to retry.';
      }

      // ── True CBVR: Gemini Vision analyzes actual video frames ──
      setState(() {
        loadingText = 'Analyzing video content (CBVR)...';
      });
      String visualDescription = '';
      try {
        visualDescription = await AiService.generateVisualDescription(thumbnailUrl);
      } catch (_) {
        visualDescription = '';
      }

      _progressTimer?.cancel();
      setState(() {
        loadingPercentage = 100;
        loadingText = 'Submitting to database...';
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;

      await FirebaseFirestore.instance.collection('films').add({
        'title': title,
        'director': directorController.text.trim(),
        'description': desc,
        'genre': _selectedGenre,
        'year': DateTime.now().year,
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'uploadedBy': uid,
        'uploaderName': FirebaseAuth.instance.currentUser?.email?.split('@')[0],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'aiSummary': aiSummary,
        'aiKeywords': aiKeywords,
        'visualDescription': visualDescription,
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
    _progressTimer?.cancel();
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
              initialValue: _selectedGenre,
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
                    // ignore: deprecated_member_use
                    groupValue: _isNewDocumentary,
                    title: const Text('New Documentary', style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF4CAF50),
                    contentPadding: EdgeInsets.zero,
                    // ignore: deprecated_member_use
                    onChanged: (val) => setState(() => _isNewDocumentary = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    value: false,
                    // ignore: deprecated_member_use
                    groupValue: _isNewDocumentary,
                    title: const Text('Old Documentary', style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF4CAF50),
                    contentPadding: EdgeInsets.zero,
                    // ignore: deprecated_member_use
                    onChanged: (val) => setState(() => _isNewDocumentary = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Video File Picker
            const Text('Video File', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4CAF50),
                      side: const BorderSide(color: Color(0xFF2E5C3E)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_library_rounded),
                    label: Text(_selectedVideoFile != null
                        ? 'Video Selected: ${_selectedVideoFile!.name}'
                        : 'Select Video File'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cover Photo Picker (Optional)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2E5C3E)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _pickCoverPhoto,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_selectedCoverPhoto != null
                        ? 'Cover Photo: ${_selectedCoverPhoto!.name}'
                        : 'Select Cover Photo (Optional)'),
                  ),
                ),
              ],
            ),

            if (_selectedCoverPhoto != null && _selectedCoverPhoto!.path != null) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cover Photo Preview:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _selectedCoverPhoto = null;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_selectedCoverPhoto!.path!),
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Video Preview
            if (_selectedVideoFile != null && _selectedVideoFile!.path != null) ...[
              const Text('Preview:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white)),
              const SizedBox(height: 8),
              CustomVideoPlayer(
                key: ValueKey(_selectedVideoFile!.path),
                videoFile: File(_selectedVideoFile!.path!),
                autoPlay: false,
              ),
              const SizedBox(height: 16),
            ],


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
                      const Color(0xFF2E7D52).withValues(alpha: 0.6),
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
