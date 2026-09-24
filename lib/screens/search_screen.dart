import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/film.dart';
import '../services/cbvr_service.dart';
import '../widgets/cbvr_result_card.dart';
import 'film_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final String initialGenre;
  final bool isViewAllMode;
  const SearchScreen({
    super.key,
    this.initialGenre = 'All',
    this.isViewAllMode = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  late String _selectedGenre;

  // -- CBVR state ----------------------------------------------------
  bool _cbvrLoading = false;
  String? _cbvrError;
  List<CbvrResult> _cbvrResults = [];
  String _lastCbvrQuery = ''; // the query that produced the current results
  Timer? _debounce;
  // --------------------------------------------------------------------

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
        ...films
            .expand((f) => f.genres.isNotEmpty ? f.genres : [f.genre])
            .toSet(),
      ];

  List<Film> _results(List<Film> films) {
    return films.where((film) {
      final q = _query.toLowerCase();
      final filmGenres = film.genres.isNotEmpty ? film.genres : [film.genre];
      final matchesQuery = _query.isEmpty ||
          film.title.toLowerCase().contains(q) ||
          film.director.toLowerCase().contains(q) ||
          filmGenres.any((g) => g.toLowerCase().contains(q)) ||
          film.description.toLowerCase().contains(q) ||
          film.aiKeywords.any((k) => k.toLowerCase().contains(q)) ||
          film.cbvrKeywords.any((k) => k.toLowerCase().contains(q));
      final matchesGenre =
          _selectedGenre == 'All' || filmGenres.contains(_selectedGenre);
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
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1A0F),
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isViewAllMode ? 'View All' : 'Search',
          style: const TextStyle(
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

          // ✅ NEW: on a wide (desktop/Chrome) window this whole page --
          // search bar, genre chips, results grid, and the AI/CBVR result
          // list -- used to stretch edge-to-edge across the entire browser
          // width. Now capped and centered at a readable max width, same
          // as the rest of the app. On an actual phone (width <= 600) this
          // has zero effect.
          final isWide = MediaQuery.of(context).size.width > 600;

          return Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
              child: Column(
                children: [
                  // -- Search bar ------------------------------------------
                  if (!widget.isViewAllMode)
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
                            });
                            if (_debounce?.isActive ?? false)
                              _debounce!.cancel();
                            if (v.trim().isEmpty) {
                              setState(() {
                                _cbvrResults = [];
                                _lastCbvrQuery = '';
                                _cbvrLoading = false;
                              });
                              return;
                            }
                            _debounce =
                                Timer(const Duration(milliseconds: 800), () {
                              if (_query.trim().isNotEmpty) {
                                _runSmartSearch(allFilms);
                              }
                            });
                          },
                          onSubmitted: (_) {
                            if (_debounce?.isActive ?? false)
                              _debounce!.cancel();
                            if (_query.trim().isNotEmpty) {
                              _runSmartSearch(allFilms);
                            }
                          },
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search films, genres, themes...',
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
                                        _lastCbvrQuery = '';
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
                  if (!widget.isViewAllMode) const SizedBox(height: 8),

                  if (!widget.isViewAllMode) const SizedBox(height: 10),

                  // -- Genre filter chips (only shown when not searching) --
                  // ✅ CHANGED: chips used to sit tight against each other and
                  // against the edge of the screen (right: 8 gap, 14 horizontal
                  // padding) -- fine on a phone, but cramped-looking on a wide
                  // desktop window. Now given more breathing room: bigger gap
                  // between chips, wider internal padding, and a taller pill.
                  if (_query.isEmpty) ...[
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: genres.length,
                        itemBuilder: (_, i) {
                          final genre = genres[i];
                          final selected = _selectedGenre == genre;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedGenre = genre),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 18),
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

                  // -- Results area ------------------------------------------
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child:
                          CircularProgressIndicator(color: Color(0xFF4CAF50)),
                    )
                  else if (_query.isNotEmpty)
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
                      // ✅ CHANGED: this grid used to force exactly 2 columns
                      // (SliverGridDelegateWithFixedCrossAxisCount) no matter
                      // how wide the window was, so on a wide desktop browser
                      // each of those 2 columns became extremely wide -- and
                      // since the card's aspect ratio is fixed (0.65), a wider
                      // card also means a much TALLER card, which is why the
                      // cards looked huge/oversized. Now using
                      // SliverGridDelegateWithMaxCrossAxisExtent instead: each
                      // card is capped at 200px wide, so a wide window simply
                      // shows MORE columns instead of 2 giant ones. On an
                      // actual phone (narrow width) this still shows 2 columns,
                      // same as before.
                      child: results.isEmpty
                          ? _buildEmpty()
                          : GridView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
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
              ),
            ),
          );
        },
      ),
    );
  }

  // -- Smart Search result panel --------------------------------------
  Widget _buildSmartResults(List<Film> allFilms) {
    // 1. Get Local Results
    final localResults = allFilms.where((film) {
      final q = _query.toLowerCase();
      if (q.isEmpty) return false;
      final filmGenres = film.genres.isNotEmpty ? film.genres : [film.genre];
      return film.title.toLowerCase().contains(q) ||
          film.director.toLowerCase().contains(q) ||
          filmGenres.any((g) => g.toLowerCase().contains(q)) ||
          film.description.toLowerCase().contains(q) ||
          film.aiKeywords.any((k) => k.toLowerCase().contains(q)) ||
          film.cbvrKeywords.any((k) => k.toLowerCase().contains(q));
    }).toList();

    // 2. Get Unique AI Results
    final localIds = localResults.map((f) => f.id).toSet();
    final uniqueCbvr =
        _cbvrResults.where((r) => !localIds.contains(r.filmId)).toList();
    final filmMap = {for (final f in allFilms) f.id: f};

    // If completely empty (no local, no AI, no loading, no error)
    if (localResults.isEmpty &&
        uniqueCbvr.isEmpty &&
        !_cbvrLoading &&
        _lastCbvrQuery.isNotEmpty &&
        _cbvrError == null) {
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
                  'No matches for "$_query"',
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

    return Expanded(
      child: CustomScrollView(
        slivers: [
          // Loading indicator
          if (_cbvrLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: Color(0xFF4CAF50),
                          strokeWidth: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Analyzing with AI...',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Finding the most relevant films for you',
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Error
          if (_cbvrError != null)
            SliverToBoxAdapter(
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

          // Local Results Header
          if (localResults.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '${localResults.length} local result${localResults.length == 1 ? '' : 's'} for "$_query"',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),

          // Local Results Grid
          // ✅ CHANGED: same fix as the main grid above -- capped card
          // width (maxCrossAxisExtent) instead of a fixed 2-column count,
          // so cards no longer stretch huge on a wide desktop window.
          if (localResults.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.65,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _filmCard(localResults[i]),
                  childCount: localResults.length,
                ),
              ),
            ),

          // Space between lists
          if (localResults.isNotEmpty && uniqueCbvr.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // AI Results Header
          if (uniqueCbvr.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Color(0xFF4CAF50), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${uniqueCbvr.length} AI result${uniqueCbvr.length != 1 ? 's' : ''} for "$_query"',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // AI Results List
          if (uniqueCbvr.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final r = uniqueCbvr[i];
                  final film = filmMap[r.filmId];
                  if (film == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CbvrResultCard(
                      film: film,
                      result: r,
                      animationIndex: i,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => FilmDetailScreen(film: film)),
                      ),
                    ),
                  );
                },
                childCount: uniqueCbvr.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // -- Normal search widgets (unchanged) ------------------------------
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white24, size: 64),
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
                    imageUrl: film.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFF1A3528),
                      child: const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF1A3528),
                      child: const Center(
                        child: Icon(Icons.movie_creation_outlined,
                            color: Colors.white54, size: 24),
                      ),
                    ),
                  )
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
