import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/film.dart';
import 'film_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final String initialGenre;
  const SearchScreen({super.key, this.initialGenre = 'All'});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  late String _selectedGenre;

  @override
  void initState() {
    super.initState();
    _selectedGenre = widget.initialGenre;
  }

  Stream<List<Film>> get _filmsStream => FirebaseFirestore.instance
      .collection('films')
      .where('status', isEqualTo: 'approved')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(Film.fromFirestore).toList());

  List<String> _genres(List<Film> films) => [
        'All',
        ...films.map((f) => f.genre).toSet().toList(),
      ];

  List<Film> _results(List<Film> films) {
    return films.where((film) {
      final matchesQuery = _query.isEmpty ||
          film.title.toLowerCase().contains(_query.toLowerCase()) ||
          film.genre.toLowerCase().contains(_query.toLowerCase()) ||
          film.description.toLowerCase().contains(_query.toLowerCase());
      final matchesGenre =
          _selectedGenre == 'All' || film.genre == _selectedGenre;
      return matchesQuery && matchesGenre;
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F17),
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Search',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4CAF50)),
        ),
      ),
      body: StreamBuilder<List<Film>>(
        stream: _filmsStream,
        builder: (context, snapshot) {
          final allFilms = snapshot.data ?? [];
          final genres = _genres(allFilms);
          final results = _results(allFilms);

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2E22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A4535)),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search films, genres...',
                      hintStyle: const TextStyle(
                          color: Colors.white38, fontSize: 14),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.white38, size: 22),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white38, size: 20),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

              // Genre filter chips
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: genres.length,
                  itemBuilder: (_, i) {
                    final genre = genres[i];
                    final selected = _selectedGenre == genre;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedGenre = genre),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFF1A2E22),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: selected
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFF2A4535)),
                          ),
                          child: Center(
                            child: Text(genre,
                                style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Results
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        _query.isEmpty && _selectedGenre == 'All'
                            ? 'All Films'
                            : '${results.length} result${results.length != 1 ? 's' : ''} found',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: results.isEmpty
                      ? _buildEmpty()
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.65,
                          ),
                          itemCount: results.length,
                          itemBuilder: (_, i) => _filmCard(results[i]),
                        ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded,
              color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          Text(
            _query.isEmpty ? 'No films available' : 'No results for "$_query"',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 15,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try a different keyword or genre',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _filmCard(Film film) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FilmDetailScreen(film: film))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            film.thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: film.thumbnailUrl, fit: BoxFit.cover)
                : Container(color: const Color(0xFF1A3528)),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xEE000000), Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(film.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${film.year} • ${film.genre}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 12),
                    const SizedBox(width: 3),
                    Text('${film.rating}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
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
