import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/film.dart';

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
        backgroundColor: const Color(0xFF0D1F17),
        appBar: AppBar(
          title: const Text('My Watchlist',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          backgroundColor: const Color(0xFF0D1F17),
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            'Please log in to view your watchlist',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final uid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      appBar: AppBar(
        title: const Text('My Watchlist',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF0D1F17),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
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
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
            );
          }

          // Error
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Something went wrong.',
                style: TextStyle(color: Colors.white54),
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
                      size: 64, color: Colors.white24),
                  SizedBox(height: 12),
                  Text(
                    'No films saved yet',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap + Watchlist on any film to save it here',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          // List
          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
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

              return _WatchlistCard(film: film, uid: uid);
            },
          );
        },
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  final Film film;
  final String uid;
  const _WatchlistCard({required this.film, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('films')
          .doc(film.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final data = snapshot.data!.data() as Map<String, dynamic>?;

        // Hide and remove if the film is deleted or returned
        if (!snapshot.data!.exists ||
            data == null ||
            data['status'] == 'returned') {
          Future.microtask(() {
            FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('watchlist')
                .doc(film.id)
                .delete();
          });
          return const SizedBox.shrink();
        }

        final currentFilm = Film(
          id: film.id,
          title: data['title'] ?? film.title,
          genre: data['genre'] ?? film.genre,
          year: data['year'] is int
              ? data['year']
              : int.tryParse('${data['year']}') ?? film.year,
          rating: data['rating'] != null
              ? (data['rating'] as num).toDouble()
              : film.rating,
          thumbnailUrl: data['thumbnailUrl'] ?? film.thumbnailUrl,
          description: data['description'] ?? film.description,
          videoUrl: data['videoUrl'] ?? film.videoUrl,
          uploadedBy: data['uploadedBy'] ?? film.uploadedBy,
          uploaderName: data['uploaderName'] ?? film.uploaderName,
          status: data['status'] ?? film.status,
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FilmDetailScreen(film: currentFilm)),
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2E22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A4535), width: 0.5),
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
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
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
                              '${currentFilm.rating.toStringAsFixed(1)}  •  ${currentFilm.genre}  •  ${currentFilm.year}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
        width: 80,
        height: 56,
        color: const Color(0xFF1A3528),
        child:
            const Icon(Icons.movie_outlined, color: Colors.white24, size: 28),
      );
}
