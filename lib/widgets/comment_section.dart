import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/comment.dart';

/// Comment section for a film. Drop this under the AI summary in
/// watch_screen.dart. Requires the film's Firestore document id.
class CommentSection extends StatefulWidget {
  final String filmId;

  const CommentSection({super.key, required this.filmId});

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  static const _greenPrime = Color(0xFF4CAF50);
  static const _textMuted = Colors.white60;

  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;

  CollectionReference<Map<String, dynamic>> get _commentsRef =>
      FirebaseFirestore.instance
          .collection('films')
          .doc(widget.filmId)
          .collection('comments');

  Future<void> _submitComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to comment.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _commentsRef.add(
        Comment(
          id: '',
          userId: user.uid,
          userName: user.displayName ?? 'Student',
          text: text,
        ).toFirestore(),
      );
      _controller.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _timeAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(color: Colors.grey),
        const SizedBox(height: 12),
        const Text(
          'Comments',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),

        // Input row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: const TextStyle(color: _textMuted),
                  filled: true,
                  fillColor: const Color(0xFF16241C),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _isSubmitting
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _greenPrime),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send_rounded, color: _greenPrime),
                    onPressed: _submitComment,
                  ),
          ],
        ),
        const SizedBox(height: 16),

        // Comment list
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              _commentsRef.orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Could not load comments.',
                    style: TextStyle(color: _textMuted)),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: CircularProgressIndicator(color: _greenPrime)),
              );
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No comments yet. Be the first!',
                    style: TextStyle(color: _textMuted)),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                final comment = Comment.fromFirestore(docs[i]);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _greenPrime.withOpacity(0.2),
                      child: Text(
                        comment.userName.isNotEmpty
                            ? comment.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: _greenPrime,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                comment.userName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _timeAgo(comment.createdAt),
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            comment.text,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}
