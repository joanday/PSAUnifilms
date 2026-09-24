import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/film.dart';
import 'film_detail_screen.dart';

class ThemeFilmsScreen extends StatelessWidget {
  final String genre;
  const ThemeFilmsScreen({super.key, required this.genre});

  // ✅ CHANGED: a film can now be tagged under MULTIPLE genres (see Submit
  // Film's new multi-select), stored in a 'genres' array field. This used
  // to query the old single-value 'genre' field with isEqualTo, which would
  // miss any film that has this genre as one of several tags instead of
  // its only one. arrayContains matches this genre being ANYWHERE in that
  // film's genres list.
  Stream<List<Film>> get _filmsStream => FirebaseFirestore.instance
          .collection('films')
          .where('status', isEqualTo: 'approved')
          .where('genres', arrayContains: genre)
          .snapshots()
          .map((snap) {
        final films = snap.docs.map(Film.fromFirestore).toList();
        // Sort locally to avoid needing a new Firestore Composite Index
        films.sort((a, b) => (b.createdAt ?? DateTime.now())
            .compareTo(a.createdAt ?? DateTime.now()));
        return films;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '$genre Documentaries',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<Film>>(
        stream: _filmsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading films',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          final films = snapshot.data ?? [];
          if (films.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.movie_filter,
                      color: Colors.white24, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'No $genre films available yet.',
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          // ✅ CHANGED: cards used to be tall/portrait (childAspectRatio
          // 0.65, i.e. narrower than tall -- like a movie poster). Now
          // landscape (wider than tall, like a real video thumbnail), and
          // the max card width is picked per screen size so the grid still
          // fills the row evenly on both a phone and a wide desktop window
          // instead of leaving a big empty gap on one side. The aspect
          // ratio is a bit shorter than a plain 16:9 now because the title
          // + producer/rating/views block below the thumbnail (see
          // _filmCard) needs its own room inside the same fixed-height grid
          // cell -- see _metaBlockHeight below.
          final isWide = MediaQuery.of(context).size.width > 600;
          final maxCardWidth = isWide ? 260.0 : 190.0;
          final cardAspectRatio = isWide ? 1.1 : 0.95;

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            // SliverGridDelegateWithMaxCrossAxisExtent (instead of a fixed
            // crossAxisCount) means the number of columns is calculated
            // from the available width divided by maxCrossAxisExtent, so a
            // wide window automatically gets MORE columns rather than a
            // few giant ones -- this also keeps the leftover space evenly
            // split as side/between-card gaps no matter how many
            // documentaries (10 or otherwise) end up in the grid.
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxCardWidth,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: cardAspectRatio,
            ),
            itemCount: films.length,
            itemBuilder: (_, i) => _filmCard(context, films[i]),
          );
        },
      ),
    );
  }

  // ✅ CHANGED: title/details used to be overlaid ON TOP of the thumbnail
  // (with a dark gradient behind them), and the second line showed who
  // uploaded it. Now the thumbnail is plain (nothing on top of it), and
  // the title + Producer(s) + rating + views sit in their own block BELOW
  // it, matching the mockup. This fixed height (not just however tall the
  // text happens to be) is what the grid's childAspectRatio above is sized
  // around -- the thumbnail gets an Expanded above it, so it simply fills
  // whatever vertical space is left in the grid cell instead of a fixed
  // 16:9, which is what keeps this from ever overflowing.
  static const double _metaBlockHeight = 72;

  Widget _filmCard(BuildContext context, Film film) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FilmDetailScreen(film: film),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF1A2E22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CachedNetworkImage(
                imageUrl: film.thumbnailUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF4CAF50))),
                errorWidget: (context, url, error) => const Icon(
                    Icons.movie_creation_outlined,
                    color: Colors.white38),
              ),
            ),
            SizedBox(
              height: _metaBlockHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      film.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // ✅ CHANGED: was an icon + bare name -- now plain text
                    // labeled "The Producers: ...", same wording as the
                    // Watching screen (film_detail_screen.dart), instead of
                    // an icon that didn't say what the name meant. Still
                    // falls back to the uploader's name if no
                    // director/producer was entered at upload time.
                    Text(
                      film.director.isNotEmpty
                          ? 'The Producers: ${film.director}'
                          : 'Uploaded by ${film.uploaderName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                    // Rating + views
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFFC107), size: 12),
                        const SizedBox(width: 2),
                        Text(
                          film.ratingCount > 0
                              ? film.rating.toStringAsFixed(1)
                              : 'No ratings',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.visibility_outlined,
                            color: Colors.white54, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          '${film.viewCount}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
