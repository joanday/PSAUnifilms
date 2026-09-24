import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/custom_video_player.dart';
import '../services/bunny_service.dart';
import '../utils/blob_url.dart';
import '../utils/genres.dart';

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

  // Web-only: a temporary browser "blob:" URL built from the picked file's
  // in-memory bytes, so CustomVideoPlayer has something it can actually
  // play in Chrome (it can't use a real file path there).
  String? _webPreviewUrl;

  bool _isLoading = false;
  // Tracks whether THIS submission got far enough (Firestore doc written)
  // that _trackProcessing should take over the loading UI, instead of the
  // normal try/finally teardown clearing it out immediately.
  bool _submittedOk = false;
  String _loadingText = '';
  int _loadingPercentage = 0;
  // Polls Bunny.net for real encode-progress while the video is being
  // encoded, after the upload itself has finished.
  Timer? _progressTimer;
  // Safety net -- if processing never finishes for some reason, this stops
  // the spinner after a while instead of leaving it stuck forever.
  Timer? _processingTimeout;
  // Listens to the film's own Firestore doc so we know the exact moment
  // the Cloud Function flips it to 'approved' (encoding + AI analysis
  // both actually done).
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  bool _isNewDocumentary = true;

  // ✅ CHANGED: was a single Dropdown value (_selectedGenre) -- a video can
  // now be tagged under every genre that actually applies to it (e.g. a
  // farming documentary about a local festival can be both "Agriculture"
  // AND "Culture"), instead of being forced to pick just one.
  final Set<String> _selectedGenres = {};

  @override
  void dispose() {
    _titleController.dispose();
    _directorController.dispose();
    _descController.dispose();
    _progressTimer?.cancel();
    _processingTimeout?.cancel();
    _statusSub?.cancel();
    if (_webPreviewUrl != null) {
      revokeBlobUrl(_webPreviewUrl!);
    }
    super.dispose();
  }

  // Guesses a video MIME type from the picked file's extension, so the
  // browser knows how to play the blob URL. Falls back to a generic mp4
  // hint if the extension is missing/unrecognized -- most browsers will
  // still sniff the real format from the bytes themselves.
  String _guessMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'video/mp4';
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      // On web there's no real filesystem path, so the file's bytes are
      // the only usable data. On mobile/desktop we keep this false and
      // stream from the path instead, to avoid loading a huge video
      // entirely into memory.
      withData: kIsWeb,
    );

    if (result != null && result.files.isNotEmpty) {
      final picked = result.files.first;

      // Clear out any previous blob URL before making a new one, so we
      // don't leak memory in the browser tab across repeated selections.
      if (_webPreviewUrl != null) {
        revokeBlobUrl(_webPreviewUrl!);
      }

      String? newPreviewUrl;
      if (kIsWeb && picked.bytes != null) {
        newPreviewUrl =
            createBlobUrl(picked.bytes!, _guessMimeType(picked.extension));
      }

      setState(() {
        _selectedVideoFile = picked;
        _webPreviewUrl = newPreviewUrl;
      });
    }
  }

  void _resetForm() {
    _titleController.clear();
    _directorController.clear();
    _descController.clear();
    if (_webPreviewUrl != null) {
      revokeBlobUrl(_webPreviewUrl!);
    }
    setState(() {
      _selectedVideoFile = null;
      _selectedGenres.clear();
      _webPreviewUrl = null;
    });
  }

  Future<void> _submitFilm() async {
    final title = _titleController.text.trim();
    final director = _directorController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty || director.isEmpty || _selectedVideoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please fill all required fields (Title, The Producers, Video File).'),
        ),
      );
      return;
    }

    if (_selectedGenres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one theme/genre.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _submittedOk = false;
      _loadingText = 'Preparing upload...';
      _loadingPercentage = 0;
    });

    try {
      // 1. Create Video Object in Bunny Stream
      setState(() => _loadingText = 'Creating video in Bunny.net...');
      final guid = await BunnyService.createVideoObject(title);

      // 2. Upload Video Bytes using TUS
      // A small early bump (instead of staying at 0%) so something is
      // visibly happening even before the first upload chunk finishes.
      setState(() {
        _loadingText = 'Uploading video file...';
        _loadingPercentage = 5;
      });
      await BunnyService.uploadVideo(
        guid,
        title,
        _selectedVideoFile!,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _loadingPercentage = progress.toInt();
              // A fresh progress update means the connection is fine
              // again, so clear any leftover "retrying..." message.
              _loadingText = 'Uploading video file...';
            });
          }
        },
        // ✅ NEW: if a chunk has to be retried (slow/dropped connection),
        // this shows it instead of the screen just looking frozen while
        // it quietly retries in the background.
        onStatus: (message) {
          if (mounted) {
            setState(() {
              _loadingText = message;
            });
          }
        },
      );

      // 3. Construct URLs
      final videoUrl = BunnyService.getDirectPlayUrl(guid);
      String thumbnailUrl = BunnyService.getThumbnailUrl(guid);

      // NOTE: no client-side AI calls here anymore. The Cloud Function
      // generateCBVRMetadata (triggered by onDocumentCreated below)
      // handles the real video+audio analysis and fills in aiSummary,
      // aiKeywords, and cbvrData once processing completes.

      _progressTimer?.cancel();
      setState(() {
        _loadingPercentage = 100;
        _loadingText = 'Saving to database...';
      });

      final docRef = await FirebaseFirestore.instance.collection('films').add({
        'title': title,
        'director': director,
        'description': desc,
        // ✅ CHANGED: a film can now belong to more than one genre. 'genres'
        // is the full list of everything selected; 'genre' is kept too
        // (set to the first selected genre) so any screen that still reads
        // the old single-genre field -- Browse by Theme's card labels,
        // Film Detail's genre chip -- keeps working without changes there.
        'genres': _selectedGenres.toList(),
        'genre': _selectedGenres.first,
        'year': DateTime.now().year,
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'uploadedBy': FirebaseAuth.instance.currentUser?.uid,
        'uploaderName': FirebaseAuth.instance.currentUser?.email?.split('@')[0],
        // ✅ CHANGED: this used to go straight to 'approved', which made a
        // film show up on Watch/Search the instant its Firestore doc was
        // created -- even while Bunny was still encoding it and the AI
        // (generateCBVRMetadata) hadn't finished writing its summary yet.
        // Now it starts as 'processing' (HomeScreen's films query only
        // shows status == 'approved', so this alone keeps it hidden), and
        // the Cloud Function flips it to 'approved' once encoding + the AI
        // analysis are both actually done.
        'status': 'processing',
        'createdAt': FieldValue.serverTimestamp(),
        'aiSummary': '',
        'aiKeywords': <String>[],
        'visualDescription': '',
        'isOldDocumentary': !_isNewDocumentary,
        'cbvrStatus': 'processing',
      });

      _submittedOk = true;

      if (mounted) {
        // Clear the form fields now that the upload itself is done. The
        // Submit button stays disabled (via _isLoading) until this film
        // finishes encoding + AI analysis below -- the progress card can
        // only track one film at a time, so this avoids a second upload
        // starting and mixing its progress with this one's.
        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Video uploaded! Now encoding + analyzing with AI...'),
            backgroundColor: Color(0xFF2E7D52),
            duration: Duration(seconds: 3),
          ),
        );
      }

      _trackProcessing(guid, docRef.id);
    } catch (e) {
      // Real error goes to the console for debugging, not to the user.
      debugPrint('Submission failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Something went wrong while submitting your film. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Only tear the loading UI down here on the FAILURE path -- on
      // success, _trackProcessing owns _isLoading from this point on, so
      // the progress card can keep showing real encoding/AI progress
      // instead of disappearing the instant the Firestore write finishes.
      if (!_submittedOk) {
        _progressTimer?.cancel();
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // ✅ NEW: keeps the progress card alive after the upload itself finishes,
  // now tracking Bunny.net's real encode progress and then the Cloud
  // Function's AI analysis -- instead of the progress just vanishing with
  // a "still processing in the background, somewhere" message and no way
  // to see it actually happen.
  Future<void> _trackProcessing(String guid, String filmDocId) async {
    // If a PREVIOUS submission's processing is still being tracked (she
    // submitted another film before the last one finished encoding/
    // analyzing), stop watching that one first -- the progress card can
    // only show one film at a time, and the older film keeps processing
    // fine server-side regardless of whether we're still listening.
    _progressTimer?.cancel();
    _statusSub?.cancel();
    _processingTimeout?.cancel();

    bool encodingDone = false;

    if (mounted) {
      setState(() {
        _loadingText = 'Encoding video...';
        _loadingPercentage = 0;
      });
    }

    // Stage 1: poll Bunny for its real encode-progress percentage.
    _progressTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || encodingDone) {
        timer.cancel();
        return;
      }
      try {
        final status = await BunnyService.getVideoStatus(guid);
        final bunnyStatus = status['status'] as int;
        final encodeProgress = (status['encodeProgress'] as num).toInt();
        // Bunny status >= 4 means encoding is finished (4 = Finished; 5/6
        // are error states, which we also treat as "done trying" here --
        // the Firestore listener below is still the real source of truth
        // for whether the film ends up fully processed.)
        if (bunnyStatus >= 4) {
          encodingDone = true;
          timer.cancel();
          if (mounted) {
            setState(() {
              _loadingText = 'Analyzing content with AI...';
              // 0 shows the indeterminate (bouncing) bar -- there's no
              // granular percentage available for the AI analysis step.
              _loadingPercentage = 0;
            });
          }
        } else if (mounted) {
          setState(() {
            _loadingText = 'Encoding video...';
            _loadingPercentage = encodeProgress.clamp(0, 99);
          });
        }
      } catch (e) {
        // A single failed status check shouldn't derail anything -- just
        // skip this tick and try again in 3 seconds.
        debugPrint('Encode status check failed: $e');
      }
    });

    // Stage 2 (runs in parallel from the start): the Cloud Function flips
    // this film's Firestore doc to status 'approved' once BOTH encoding
    // and AI analysis are actually done -- that's the true completion
    // signal, not just Bunny's encode status.
    _statusSub = FirebaseFirestore.instance
        .collection('films')
        .doc(filmDocId)
        .snapshots()
        .listen((doc) {
      if (doc.data()?['status'] == 'approved') {
        _finishProcessing(success: true);
      }
    });

    // Safety net: if something never resolves (Cloud Function error, etc.)
    // don't leave the spinner running forever.
    _processingTimeout = Timer(const Duration(minutes: 6), () {
      _finishProcessing(success: false);
    });
  }

  void _finishProcessing({required bool success}) {
    _progressTimer?.cancel();
    _statusSub?.cancel();
    _processingTimeout?.cancel();
    if (!mounted) return;

    setState(() {
      _loadingPercentage = 100;
      _loadingText = success ? 'Done!' : 'Still processing...';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Your film is fully processed and now live on Watch!'
            : "Taking longer than expected -- it's still processing in the background and will appear on Watch once it's ready."),
        backgroundColor:
            success ? const Color(0xFF2E7D52) : const Color(0xFF8A6D00),
        duration: const Duration(seconds: 5),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ CHANGED: per the reference mockup, the form is just centered on
    // the plain page background now -- no bordered/tinted "card" box
    // around it (that panel look was making this screen read as a
    // different color/shade than the rest of the app). On an actual phone
    // (width <= 600) this has no effect: the form stays exactly as it was.
    final isWide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      // ✅ CHANGED: was 0xFF0D1F17 -- now 0xFF0F1A0F, matching
      // manage_users_screen.dart's page background exactly (Watch/Users/
      // Upload/Profile all share one uniform background color now).
      backgroundColor: const Color(0xFF0F1A0F),
      // ✅ CHANGED: dropped the AppBar title -- it used to sit pinned to the
      // far left of a bar spanning the FULL browser width, which looked
      // disconnected once everything below it became a centered 640-wide
      // column. "Submit Film" is now a heading inside that same centered
      // column instead (identical style/position to the "User Management"
      // heading on the Users screen), so it's centered on the page along
      // with everything else instead of floating on its own at the left.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
            child: Container(
              padding: isWide
                  ? const EdgeInsets.symmetric(vertical: 8)
                  : EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: double.infinity,
                    child: Text('Submit Film',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 16),
                  // ── Upload/processing progress card ─────────────────────────
                  // Shows right at the top of the screen (instead of just inside
                  // the button label) so it's clearly visible while uploading.
                  if (_isLoading) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3528),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E5C3E)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _loadingText,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$_loadingPercentage%',
                                style: const TextStyle(
                                    color: Color(0xFF4CAF50),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              // Indeterminate (bouncing) bar during the steps
                              // before we have a real byte-by-byte percentage
                              // (creating the video object in Bunny), then a real
                              // determinate bar once the upload itself starts.
                              value: _loadingPercentage > 0
                                  ? _loadingPercentage / 100
                                  : null,
                              minHeight: 8,
                              backgroundColor: const Color(0xFF0D1F17),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF4CAF50)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

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
                      prefixIcon:
                          const Icon(Icons.movie, color: Colors.white38),
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
                  const Text('The Producers',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _directorController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. Juan Dela Cruz',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1A3528),
                      prefixIcon:
                          const Icon(Icons.person, color: Colors.white38),
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
                  const Text('Description (Optional)',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          'Leave blank to let AI Insight generate it automatically...',
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
                  const Text('Theme (select all that apply)',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  // ✅ CHANGED: was a Dropdown that only let you pick ONE genre --
                  // now a grid of selectable chips, so a video can be tagged
                  // under every genre that actually fits it. Uses the same
                  // uniform icon set as Home's "Browse by Theme" chips (see
                  // utils/genres.dart) instead of the old plain-text dropdown
                  // items.
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kGenres.map((genreInfo) {
                      final selected =
                          _selectedGenres.contains(genreInfo.label);
                      return FilterChip(
                        selected: selected,
                        onSelected: (isSelected) {
                          setState(() {
                            if (isSelected) {
                              _selectedGenres.add(genreInfo.label);
                            } else {
                              _selectedGenres.remove(genreInfo.label);
                            }
                          });
                        },
                        avatar: Icon(genreInfo.icon,
                            size: 18,
                            color: selected ? Colors.white : Colors.white54),
                        label: Text(genreInfo.label),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                        backgroundColor: const Color(0xFF1A3528),
                        selectedColor: const Color(0xFF2E7D52),
                        checkmarkColor: Colors.white,
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF2E5C3E),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Documentary Type',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          value: true,
                          // ignore: deprecated_member_use
                          groupValue: _isNewDocumentary,
                          title: const Text('New Documentary',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                          activeColor: const Color(0xFF4CAF50),
                          contentPadding: EdgeInsets.zero,
                          // ignore: deprecated_member_use
                          onChanged: (val) =>
                              setState(() => _isNewDocumentary = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          value: false,
                          // ignore: deprecated_member_use
                          groupValue: _isNewDocumentary,
                          title: const Text('Old Documentary',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                          activeColor: const Color(0xFF4CAF50),
                          contentPadding: EdgeInsets.zero,
                          // ignore: deprecated_member_use
                          onChanged: (val) =>
                              setState(() => _isNewDocumentary = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Video File',
                      style: TextStyle(color: Colors.white70)),
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
                  const SizedBox(height: 24),
                  if (!kIsWeb &&
                      _selectedVideoFile != null &&
                      _selectedVideoFile!.path != null) ...[
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
                  ] else if (kIsWeb &&
                      _selectedVideoFile != null &&
                      _webPreviewUrl != null) ...[
                    const Text('Preview:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white)),
                    const SizedBox(height: 8),
                    CustomVideoPlayer(
                      key: ValueKey(_webPreviewUrl),
                      videoUrl: _webPreviewUrl,
                      autoPlay: false,
                    ),
                    const SizedBox(height: 16),
                  ] else if (kIsWeb && _selectedVideoFile != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Preview isn\'t available for this file -- it is still selected and ready to upload.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
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
                      // Percentage now lives in the progress card above instead
                      // of being crammed into this label too.
                      label:
                          Text(_isLoading ? 'Please wait...' : 'Submit Film'),
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
          ),
        ),
      ),
    );
  }
}
