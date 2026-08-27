import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/film.dart';
import '../services/cbvr_service.dart';
import '../widgets/cbvr_result_card.dart';
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

  // ── CBVR state ──────────────────────────────────────────────
  bool _smartSearchEnabled = false;
  bool _cbvrLoading = false;
  String? _cbvrError;
  List<CbvrResult> _cbvrResults = [];
  String _lastCbvrQuery = ''; // the query that produced the current results
  // ────────────────────────────────────────────────────────────

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
        ...films.map((f) => f.genre).toSet(),
      ];

  List<Film> _results(List<Film> films) {
    return films.where((film) {
      final q = _query.toLowerCase();
      final matchesQuery = _query.isEmpty ||
          film.title.toLowerCase().contains(q) ||
          film.genre.toLowerCase().contains(q) ||
          film.description.toLowerCase().contains(q) ||
          film.aiKeywords.any((k) => k.toLowerCase().contains(q));
      final matchesGenre =
          _selectedGenre == 'All' || film.genre == _selectedGenre;
      return matchesQuery && matchesGenre;
    }).toList();
  }

  /// Runs the CBVR Gemini search against the current film list.
  Future<void> _runSmartSearch(List<Film> allFilms) async {
    if (_query.trim().isEmpty) return;
    setState(() {
      _cbvrLoading = true;
      _cbvrError = null;
      _cbvrResults = [];
    });
    try {
      final results = await CbvrService.search(_query.trim(), allFilms);
      if (mounted) {
        setState(() {
          _cbvrResults = results;
          _lastCbvrQuery = _query.trim();
          _cbvrLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cbvrError = e.toString().replaceFirst('Exception: ', '');
          _cbvrLoading = false;
        });
      }
    }
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
              // ── Search bar ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2E22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A4535)),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (v) {
                      setState(() {
                        _query = v;
                        // Clear CBVR results when query changes
                        if (_smartSearchEnabled) {
                          _cbvrResults = [];
                          _cbvrError = null;
                        }
                      });
                    },
                    onSubmitted: (_) {
                      if (_smartSearchEnabled) _runSmartSearch(allFilms);
                    },
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: _smartSearchEnabled
                          ? 'Describe what you\'re looking for...'
                          : 'Search films, genres...',
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
                                setState(() {
                                  _query = '';
                                  _cbvrResults = [];
                                  _cbvrError = null;
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

              // ── Smart Search toggle row ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    // Toggle chip
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _smartSearchEnabled = !_smartSearchEnabled;
                          _cbvrResults = [];
                          _cbvrError = null;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _smartSearchEnabled
                              ? const Color(0xFF4CAF50).withValues(alpha: 0.18)
                              : const Color(0xFF1A2E22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _smartSearchEnabled
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFF2A4535),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 13,
                              color: _smartSearchEnabled
                                  ? const Color(0xFF4CAF50)
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Smart Search',
                              style: TextStyle(
                                color: _smartSearchEnabled
                                    ? const Color(0xFF4CAF50)
                                    : Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 5),
                            AnimatedRotation(
                              turns: _smartSearchEnabled ? 0 : 0.5,
                              duration: const Duration(milliseconds: 220),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 14,
                                color: _smartSearchEnabled
                                    ? const Color(0xFF4CAF50)
                                    : Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // "Search" button (only shown in Smart Search mode)
                    if (_smartSearchEnabled) ...[
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: _query.trim().isNotEmpty ? 1.0 : 0.4,
                          duration: const Duration(milliseconds: 200),
                          child: GestureDetector(
                            onTap: _query.trim().isNotEmpty
                                ? () => _runSmartSearch(allFilms)
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Center(
                                child: Text(
                                  'Search with AI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Powered by hint
                      Expanded(
                        child: Text(
                          'Tap ✨ Smart Search to find by description',
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Genre filter chips (only in normal mode) ─────────
              if (!_smartSearchEnabled) ...[
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
                          onTap: () =>
                              setState(() => _selectedGenre = genre),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
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
              ] else ...[
                const SizedBox(height: 6),
              ],

              // ── Results area ─────────────────────────────────────
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child:
                      CircularProgressIndicator(color: Color(0xFF4CAF50)),
                )
              else if (_smartSearchEnabled)
                _buildSmartResults(allFilms)
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
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

  // ── Smart Search result panel ──────────────────────────────────
  Widget _buildSmartResults(List<Film> allFilms) {
    // Loading state
    if (_cbvrLoading) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Color(0xFF4CAF50),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Analyzing with AI...',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 6),
              const Text(
                'Finding the most relevant films for you',
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Error state
    if (_cbvrError != null) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFEF5350), size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Smart Search failed',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _cbvrError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _runSmartSearch(allFilms),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF4CAF50)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Idle — no search run yet
    if (_cbvrResults.isEmpty && _lastCbvrQuery.isEmpty) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Color(0xFF4CAF50), size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Smart Search is ON',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Describe what you\'re looking for in plain language — like "rice farming documentary" or "graduation ceremony film" — and AI will find the most relevant matches.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white38, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // No results after search
    if (_cbvrResults.isEmpty) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_rounded,
                    color: Colors.white24, size: 56),
                const SizedBox(height: 12),
                Text(
                  'No matches for "$_lastCbvrQuery"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Try rephrasing your query or use different keywords',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Build a film ID → Film lookup map for fast access
    final filmMap = {for (final f in allFilms) f.id: f};

    return Expanded(
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: Color(0xFF4CAF50), size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_cbvrResults.length} AI result${_cbvrResults.length != 1 ? 's' : ''} for "$_lastCbvrQuery"',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Result cards list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _cbvrResults.length,
              itemBuilder: (_, i) {
                final cbvrResult = _cbvrResults[i];
                final film = filmMap[cbvrResult.filmId];
                if (film == null) return const SizedBox.shrink();
                return CbvrResultCard(
                  film: film,
                  result: cbvrResult,
                  animationIndex: i,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => FilmDetailScreen(film: film)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Normal search widgets (unchanged) ─────────────────────────
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
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
