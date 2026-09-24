import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/film.dart';
import 'edit_documentary_screen.dart';

// ─── Admin-only: list of every uploaded documentary ──────────────────────────
//
// Opened from Profile > "Edit Documentary Videos". No status filter here on
// purpose -- unlike the Watch tab (which only shows status == 'approved'),
// Admin needs to see archived films too (with an "Archived" badge) so they
// can unarchive them again. Tapping a row opens EditDocumentaryScreen for
// that film.

class EditDocumentariesScreen extends StatelessWidget {
  const EditDocumentariesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ NEW: on a wide (desktop/Chrome) window this list used to stretch
    // full edge-to-edge across the whole browser width -- rows of a plain
    // list look odd that wide. Now capped at the same centered, max-640
    // layout used everywhere else in the app. On an actual phone (width
    // <= 600) this has zero effect.
    final isWide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1A0F),
        title: const Text('Edit Documentary Videos',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('films')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.greenPrime));
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('Failed to load documentaries.',
                  style: TextStyle(color: AppTheme.textMuted)),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No documentaries uploaded yet.',
                  style: TextStyle(color: AppTheme.textMuted)),
            );
          }

          final films = docs.map((d) => Film.fromFirestore(d)).toList();

          return Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: films.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _FilmTile(film: films[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilmTile extends StatelessWidget {
  final Film film;
  const _FilmTile({required this.film});

  @override
  Widget build(BuildContext context) {
    final isArchived = film.status == 'archived';

    return Material(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => EditDocumentaryScreen(filmId: film.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: film.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          film.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: AppTheme.bgCard,
                              child: const Icon(Icons.movie_outlined,
                                  color: AppTheme.textMuted)),
                        )
                      : Container(
                          color: AppTheme.bgCard,
                          child: const Icon(Icons.movie_outlined,
                              color: AppTheme.textMuted)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(film.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                        '${film.year} • ${(film.genres.isNotEmpty ? film.genres : [
                            film.genre
                          ]).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12)),
                    if (isArchived) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Archived',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ),
              // ✅ Edit icon (not a plain chevron) so it's clear tapping a
              // row opens that video for editing.
              const Icon(Icons.edit_outlined, color: AppTheme.greenPrime),
            ],
          ),
        ),
      ),
    );
  }
}
