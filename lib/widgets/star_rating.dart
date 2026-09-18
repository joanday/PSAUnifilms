import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Shows the film's average rating (read by everyone) and, for a signed-in
/// user, a row of tappable stars to submit or update their own 1-5 rating.
/// Ratings are stored per-user under films/{filmId}/ratings/{userId} and
/// averaged into the film document's `rating` / `ratingCount` fields via a
/// Firestore transaction, so the average always reflects every rater.
class StarRating extends StatefulWidget {
  final String filmId;
  final double averageRating;
  final int ratingCount;

  const StarRating({
    super.key,
    required this.filmId,
    required this.averageRating,
    required this.ratingCount,
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
  late double _localAverage;
  late int _localCount;

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
    _localAverage = widget.averageRating;
    _localCount = widget.ratingCount;
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
      double resultAverage = _localAverage;
      int resultCount = _localCount;

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

        resultAverage = newAverage;
        resultCount = newCount;
      });

      if (mounted) {
        setState(() {
          _myRating = stars;
          _localAverage = resultAverage;
          _localCount = resultCount;
        });
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
    bool half = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        IconData icon;
        if (half && starIndex == filledCount + 1 && filledCount % 1 != 0) {
          icon = Icons.star_half_rounded;
        } else {
          icon = starIndex <= filledCount
              ? Icons.star_rounded
              : Icons.star_border_rounded;
        }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _starRow(filledCount: _localAverage.round(), size: 18),
            const SizedBox(width: 8),
            Text(
              _localCount > 0
                  ? '${_localAverage.toStringAsFixed(1)} ($_localCount rating${_localCount == 1 ? '' : 's'})'
                  : 'No ratings yet',
              style: const TextStyle(color: _textMuted, fontSize: 13),
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
                _myRating != null ? 'Your rating:' : 'Rate this documentary:',
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
  }
}
