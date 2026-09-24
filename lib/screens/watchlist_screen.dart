import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/film.dart';
import '../theme/app_theme.dart';
import 'film_detail_screen.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // ✅ FIX: don't force-unwrap currentUser. If auth state is still
    // settling (or the user got signed out) when this screen builds,
    // show a safe state instead of crashing with the `!` operator.
    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1A0F),
        appBar: AppBar(
          title: const Text('My Watchlist'),
          backgroundColor: const Color(0xFF0F1A0F),
          foregroundColor: AppTheme.textPrimary,
        ),
        body: const Center(
          child: Text(
            'Please log in to view your watchlist',
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }

    final uid = user.uid;

    // ✅ CHANGED: per the reference mockup, the watchlist is just
    // centered on the plain page background now -- no bordered/tinted
    // "card" box around it. On an actual phone (width <= 600) this has
    // no effect: same plain full-width list as before.
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1A0F),
      appBar: AppBar(
        title: const Text('My Watchlist'),
        backgroundColor: const Color(0xFF0F1A0F),
        foregroundColor: AppTheme.textPrimary,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('watchlist')
                  .orderBy('addedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                // Loading
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.greenPrime),
                  );
                }

                // Error
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Something went wrong.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  );
                }

                // Empty
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_border_rounded,
                            size: 64, color: AppTheme.textMuted),
                        SizedBox(height: 12),
                        Text(
                          'No films saved yet',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap + Watchlist on any film to save it here',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                // List
                final docs = snapshot.data!.docs;
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;

                    final film = Film(
                      id: data['filmId'] ?? '',
                      title: data['title'] ?? '',
                      genre: data['genre'] ?? '',
                      year: data['year'] is int
                          ? data['year']
                          : int.tryParse('${data['year']}') ?? 2024,
                      rating: data['rating'] != null
                          ? (data['rating'] as num).toDouble()
                          : 0.0,
                      thumbnailUrl: data['thumbnailUrl'] ?? '',
                      description: data['description'] ?? '',
                      videoUrl: data['videoUrl'] ?? '',
                      uploadedBy: data['uploadedBy'] ?? '',
                      uploaderName: data['uploaderName'] ?? '',
                      status: data['status'] ?? 'approved',
                    );

                    return _WatchlistCard(film: film);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  final Film film;
  const _WatchlistCard({required this.film});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FilmDetailScreen(film: film)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: film.thumbnailUrl.isNotEmpty
                  ? Image.network(
                      film.thumbnailUrl,
                      width: 80,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    film.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        '${film.rating}  •  ${film.genre}  •  ${film.year}',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 80,
        height: 56,
        color: AppTheme.bgDark,
        child: const Icon(Icons.movie_outlined,
            color: AppTheme.textMuted, size: 28),
      );
}
