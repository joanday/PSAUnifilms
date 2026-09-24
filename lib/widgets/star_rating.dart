import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Shows the film's average rating (read by everyone) and, for a signed-in
/// user, a row of tappable stars to submit or update their own 1-5 rating.
/// Ratings are stored per-user under films/{filmId}/ratings/{userId} and
/// averaged into the film document's `rating` / `ratingCount` fields via a
/// Firestore transaction.
///
/// The average/count shown here is streamed LIVE from films/{filmId} rather
/// than taken from a value passed in by the parent -- a parent screen may
/// be holding a stale/snapshotted Film object (e.g. one built from a
/// watchlist entry, which never stores ratingCount), which previously made
/// this widget freeze at whatever count it was first built with and show
/// "No ratings yet" even when the film had real ratings.
class StarRating extends StatefulWidget {
  final String filmId;

  const StarRating({
    super.key,
    required this.filmId,
  });

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  static const _amber = Color(0xFFFFC107);
  static const _textMuted = Colors.white60;

  int? _myRating;
  bool _loadingMyRating = true;
  bool _submitting = false;

  DocumentReference<Map<String, dynamic>> get _filmRef =>
      FirebaseFirestore.instance.collection('films').doc(widget.filmId);

  DocumentReference<Map<String, dynamic>>? get _myRatingRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _filmRef.collection('ratings').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _loadMyRating();
  }

  Future<void> _loadMyRating() async {
    final ref = _myRatingRef;
    if (ref == null) {
      setState(() => _loadingMyRating = false);
      return;
    }
    try {
      final doc = await ref.get();
      if (mounted) {
        setState(() {
          _myRating = doc.data()?['rating'] as int?;
          _loadingMyRating = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMyRating = false);
    }
  }

  Future<void> _submitRating(int stars) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please log in to rate this documentary.')),
      );
      return;
    }

    final myRatingRef = _filmRef.collection('ratings').doc(user.uid);
    setState(() => _submitting = true);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Reads must happen before any writes in a Firestore transaction.
        final filmSnap = await transaction.get(_filmRef);
        final myRatingSnap = await transaction.get(myRatingRef);

        final filmData = filmSnap.data() ?? {};
        final currentSum = (filmData['ratingSum'] as num?)?.toDouble() ?? 0.0;
        final currentCount = (filmData['ratingCount'] as num?)?.toInt() ?? 0;
        final previousStars = myRatingSnap.data()?['rating'] as int?;

        final newSum = currentSum - (previousStars ?? 0) + stars;
        final newCount =
            previousStars == null ? currentCount + 1 : currentCount;
        final newAverage = newCount == 0 ? 0.0 : newSum / newCount;

        transaction.set(myRatingRef, {
          'rating': stars,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(_filmRef, {
          'ratingSum': newSum,
          'ratingCount': newCount,
          'rating': newAverage,
        });
      });

      // No need to update local average/count state here -- the
      // StreamBuilder in build() below picks up the new values live.
      if (mounted) {
        setState(() => _myRating = stars);
      }
    } catch (e) {
      debugPrint('Failed to submit rating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Couldn\'t save your rating. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _starRow({
    required int filledCount,
    required double size,
    void Function(int)? onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        final icon = starIndex <= filledCount
            ? Icons.star_rounded
            : Icons.star_border_rounded;
        final star = Icon(icon, color: _amber, size: size);
        if (onTap == null) return star;
        return InkWell(
          borderRadius: BorderRadius.circular(size),
          onTap: () => onTap(starIndex),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: star,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _filmRef.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final average = (data?['rating'] as num?)?.toDouble() ?? 0.0;
        final count = (data?['ratingCount'] as num?)?.toInt() ?? 0;
        // ✅ NEW: views, streamed live from the same films/{filmId} doc
        // (same reasoning as the rating above -- a parent screen may be
        // holding a stale/snapshotted Film object, so this reads the
        // current count directly rather than trusting a value passed in).
        final views = (data?['viewCount'] as num?)?.toInt() ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                _starRow(filledCount: average.round(), size: 18),
                Text(
                  count > 0
                      ? '${average.toStringAsFixed(1)} ($count rating${count == 1 ? '' : 's'})'
                      : 'No ratings yet',
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.visibility_outlined,
                        color: _textMuted, size: 15),
                    const SizedBox(width: 4),
                    Text(
                      '$views view${views == 1 ? '' : 's'}',
                      style: const TextStyle(color: _textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingMyRating)
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: _amber),
              )
            else
              Row(
                children: [
                  Text(
                    _myRating != null
                        ? 'Your rating:'
                        : 'Rate this documentary:',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: _submitting ? 0.5 : 1,
                    child: _starRow(
                      filledCount: _myRating ?? 0,
                      size: 26,
                      onTap: _submitting ? null : _submitRating,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
