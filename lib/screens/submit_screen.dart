import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/custom_video_player.dart';
import '../services/ai_service.dart';
import '../services/bunny_service.dart';

class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  final _titleController = TextEditingController();
  final _directorController = TextEditingController();
  final _descController = TextEditingController();
  
  PlatformFile? _selectedVideoFile;
  PlatformFile? _selectedCoverPhoto;

  bool _isLoading = false;
  String _loadingText = '';
  int _loadingPercentage = 0;
  Timer? _progressTimer;
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
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false, // Don't load entire file into memory
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

  void _resetForm() {
    _titleController.clear();
    _directorController.clear();
    _descController.clear();
    setState(() {
      _selectedVideoFile = null;
      _selectedCoverPhoto = null;
      _selectedGenre = null;
    });
  }

  Future<void> _submitFilm() async {
    final title = _titleController.text.trim();
    final director = _directorController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty || director.isEmpty || _selectedVideoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields (Title, Director, Video File).'),
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

    try {
      // 1. Create Video Object in Bunny Stream
      setState(() => _loadingText = 'Creating video in Bunny.net...');
      final guid = await BunnyService.createVideoObject(title);

      // 2. Upload Video Bytes using TUS
      setState(() => _loadingText = 'Uploading video file...');
      await BunnyService.uploadVideo(
        guid, 
        _selectedVideoFile!,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _loadingPercentage = progress.toInt();
            });
          }
        },
      );

      // 3. Construct URLs and Upload Cover Photo (if selected)
      final videoUrl = BunnyService.getDirectPlayUrl(guid);
      String thumbnailUrl = BunnyService.getThumbnailUrl(guid);

      if (_selectedCoverPhoto != null && _selectedCoverPhoto!.path != null) {
        setState(() => _loadingText = 'Uploading cover photo to Bunny.net...');
        final coverFile = File(_selectedCoverPhoto!.path!);
        if (!await coverFile.exists()) {
          throw Exception("Selected cover photo file does not exist on device.");
        }
        
        await BunnyService.uploadThumbnail(guid, coverFile);
      }

      // 4. Generate AI Metadata
      setState(() {
        _loadingText = 'Generating AI Metadata...';
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

      // 5. Visual Description (CBVR)
      setState(() {
        _loadingText = 'Analyzing video content (CBVR)...';
      });
      String visualDescription = '';
      try {
        visualDescription = await AiService.generateVisualDescription(thumbnailUrl);
      } catch (_) {
        visualDescription = '';
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
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'uploadedBy': FirebaseAuth.instance.currentUser?.uid,
        'uploaderName': FirebaseAuth.instance.currentUser?.email?.split('@')[0],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'aiSummary': aiSummary,
        'aiKeywords': aiKeywords,
        'visualDescription': visualDescription,
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

            const SizedBox(height: 8),

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
                      const Color(0xFF2E7D52).withValues(alpha: 0.6),
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
