import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/film.dart';
import '../services/cbvr_service.dart';
import '../widgets/cbvr_result_card.dart';
import '../widgets/showcase_banner.dart';
import '../widgets/user_avatar.dart';
import 'film_detail_screen.dart';
import 'search_screen.dart';
import 'theme_films_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Smart Search (CBVR) state ───────────────────────────────────
  bool _cbvrLoading = false;
  String? _cbvrError;
  List<CbvrResult> _cbvrResults = [];
  String _lastCbvrQuery = '';
  Timer? _debounce;
  // ───────────────────────────────────────────────────────────────

  final List<Map<String, String>> themes = [
    {'icon': '🌾', 'label': 'Agriculture'},
    {'icon': '🏛️', 'label': 'Culture'},
    {'icon': '🌿', 'label': 'Environment'},
    {'icon': '📚', 'label': 'Education'},
    {'icon': '🤝', 'label': 'Community'},
  ];

  Stream<List<Film>> get _filmsStream {
    return FirebaseFirestore.instance
        .collection('films')
        .where('status', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
      final films = <Film>[];
      for (var doc in snap.docs) {
        try {
          films.add(Film.fromFirestore(doc));
        } catch (e) {
          debugPrint('PARSE ERROR: $e');
        }
      }
      return films;
    });
  }

  List<Film> _filterFilms(List<Film> films) {
    if (_searchQuery.isEmpty) return films;
    final q = _searchQuery.toLowerCase();
    return films
        .where((f) =>
            f.title.toLowerCase().contains(q) ||
            f.director.toLowerCase().contains(q) ||
            f.genre.toLowerCase().contains(q) ||
            f.description.toLowerCase().contains(q) ||
            f.aiKeywords.any((k) => k.toLowerCase().contains(q)) ||
            f.cbvrKeywords.any((k) => k.toLowerCase().contains(q)))
        .toList();
  }

  void _goToSearch({String genre = 'All'}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SearchScreen(initialGenre: genre, isViewAllMode: true)),
    );
  }

  Future<void> _runSmartSearch(List<Film> allFilms) async {
    if (_searchQuery.trim().isEmpty) return;
    setState(() {
      _cbvrLoading = true;
      _cbvrError = null;
      _cbvrResults = [];
    });
    try {
      final results = await CbvrService.search(_searchQuery.trim(), allFilms);
      if (mounted) {
        setState(() {
          _cbvrResults = results;
          _lastCbvrQuery = _searchQuery.trim();
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      body: StreamBuilder<List<Film>>(
        stream: _filmsStream,
        builder: (context, snapshot) {
          final allFilms = snapshot.data ?? [];
          final films = _filterFilms(allFilms);
          final now = DateTime.now();
          final currentMonthFilms = allFilms.where((f) => 
            f.createdAt != null && 
            f.createdAt!.month == now.month && 
            f.createdAt!.year == now.year
          ).toList();
          
          final featured = currentMonthFilms.isNotEmpty 
              ? currentMonthFilms.first 
              : (allFilms.isNotEmpty ? allFilms.first : null);
          
          final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
          final newlyUploaded = allFilms
              .where((f) => f.createdAt != null && f.createdAt!.isAfter(sevenDaysAgo) && !f.isOldDocumentary)
              .take(5)
              .toList();

          return SafeArea(
            child: CustomScrollView(
              slivers: [
                // App Bar
                SliverAppBar(
                  backgroundColor: const Color(0xFF0D1F17),
                floating: true,
                title: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: AssetImage('assets/images/psaulogo.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('PSAUniFilms',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        Text('Student Films Showcase App',
                            style: TextStyle(
                                fontSize: 10, color: Colors.white54)),
                      ],
                    ),
                  ],
                ),
                actions: const [
                  UserAvatar(radius: 18, showInitialsFallback: true),
                  SizedBox(width: 16),
                ],
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Search bar + Smart Search toggle ──────────────
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2E22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Search films, genres, themes...',
                                  hintStyle: const TextStyle(
                                      color: Colors.white38, fontSize: 13),
                                  prefixIcon: const Icon(Icons.search,
                                      color: Colors.white38, size: 20),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                              _cbvrResults = [];
                                              _cbvrError = null;
                                              _lastCbvrQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                                  if (value.trim().isEmpty) {
                                    setState(() {
                                      _cbvrResults = [];
                                      _lastCbvrQuery = '';
                                      _cbvrLoading = false;
                                    });
                                    return;
                                  }
                                  _debounce = Timer(const Duration(milliseconds: 800), () {
                                    if (_searchQuery.trim().isNotEmpty) {
                                      _runSmartSearch(allFilms);
                                    }
                                  });
                                },
                                onSubmitted: (_) {
                                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                                  if (_searchQuery.trim().isNotEmpty) {
                                    _runSmartSearch(allFilms);
                                  }
                                },
                                textInputAction: TextInputAction.search,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(
                                color: Color(0xFF4CAF50)),
                          ),
                        )
                      else if (_searchQuery.isNotEmpty) ...() {
                        final List<Widget> widgets = [];

                        // 1. Loading
                        if (_cbvrLoading && films.isEmpty) {
                          widgets.add(
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                        color: Color(0xFF4CAF50), strokeWidth: 3),
                                    SizedBox(height: 14),
                                    Text('Analyzing with AI...',
                                        style: TextStyle(
                                            color: Colors.white54, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        // 2. Error
                        if (_cbvrError != null) {
                          widgets.add(
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Color(0xFFEF5350), size: 40),
                                    const SizedBox(height: 10),
                                    Text(_cbvrError!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12,
                                            height: 1.5)),
                                    const SizedBox(height: 12),
                                    GestureDetector(
                                      onTap: () => _runSmartSearch(allFilms),
                                      child: const Text('Try Again',
                                          style: TextStyle(
                                              color: Color(0xFF4CAF50),
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        // 3. Local Results
                        if (films.isNotEmpty) {
                          widgets.add(
                            Text(
                              '${films.length} local result${films.length == 1 ? '' : 's'} for "$_searchQuery"',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13),
                            ),
                          );
                          widgets.add(const SizedBox(height: 12));
                          widgets.addAll(films.map((film) => _searchResultCard(film)));
                        }

                        // 4. AI Results
                        if (_lastCbvrQuery.isNotEmpty && !_cbvrLoading) {
                          final localIds = films.map((f) => f.id).toSet();
                          final uniqueCbvr = _cbvrResults
                              .where((r) => !localIds.contains(r.filmId))
                              .toList();

                          if (uniqueCbvr.isNotEmpty) {
                            if (films.isNotEmpty) {
                              widgets.add(const SizedBox(height: 24));
                            }
                            widgets.add(
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.auto_awesome,
                                        color: Color(0xFF4CAF50), size: 13),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${uniqueCbvr.length} AI result${uniqueCbvr.length != 1 ? 's' : ''} for "$_lastCbvrQuery"',
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            final filmMap = {for (final f in allFilms) f.id: f};
                            widgets.addAll(uniqueCbvr.map((r) {
                              final film = filmMap[r.filmId];
                              if (film == null) return const SizedBox.shrink();
                              return CbvrResultCard(
                                film: film,
                                result: r,
                                animationIndex: _cbvrResults.indexOf(r),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          FilmDetailScreen(film: film)),
                                ),
                              );
                            }));
                          } else if (films.isEmpty) {
                            widgets.add(
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.auto_awesome,
                                          color: Colors.white38, size: 40),
                                      const SizedBox(height: 12),
                                      Text('No films matched "$_lastCbvrQuery"',
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        } else if (films.isEmpty && !_cbvrLoading && _lastCbvrQuery.isEmpty) {
                          widgets.add(
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Text('No films found locally',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 14)),
                              ),
                            ),
                          );
                        }

                        return widgets;
                      }()

                      // Normal home content
                      else if (allFilms.isEmpty)
                        _emptyState()
                      else ...[
                        // Featured
                        if (featured != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text('Monthly Showcase',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ShowcaseBanner(
                            films: currentMonthFilms,
                            onTap: (film) => _goToDetail(film),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Browse by Theme
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Browse by Theme',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            TextButton(
                              onPressed: () => _goToSearch(),
                              child: const Text('View All',
                                  style: TextStyle(
                                      color: Color(0xFF4CAF50),
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _themeChips(),
                        const SizedBox(height: 20),

                        // Newly Uploaded
                        if (newlyUploaded.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Newly Uploaded',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _newlyUploadedList(newlyUploaded),
                        ],
                        const SizedBox(height: 20),

                        // All Documentaries
                        const Text('All Documentaries',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 20,
                            alignment: WrapAlignment.spaceBetween,
                            children: allFilms.map((film) => _portraitFilmCard(film, context)).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ));
        },
      ),
    );
  }

  Widget _searchResultCard(Film film) {
    return GestureDetector(
      onTap: () => _goToDetail(film),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2E22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A4535), width: 0.5),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: film.thumbnailUrl.isNotEmpty
                  ? Image.network(
                      film.thumbnailUrl,
                      width: 80,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                    )
                  : _thumbPlaceholder(),
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
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${film.year} • ${film.genre}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 12),
                    const SizedBox(width: 3),
                    Text('${film.rating}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
        width: 80,
        height: 56,
        color: const Color(0xFF1A3528),
        child: const Icon(Icons.movie_outlined,
            color: Colors.white24, size: 28),
      );

  Widget _portraitFilmCard(Film film, BuildContext context) {
    // Calculate width to fit 2 items per row with 16px spacing and 16px padding on sides (total 32 + 16 = 48)
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 48) / 2;
    final cardHeight = cardWidth * 1.5; // 2:3 aspect ratio

    return GestureDetector(
      onTap: () => _goToDetail(film),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: film.thumbnailUrl.isNotEmpty
                  ? Image.network(
                      film.thumbnailUrl,
                      width: cardWidth,
                      height: cardHeight,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: cardWidth,
                        height: cardHeight,
                        color: const Color(0xFF1A3528),
                        child: const Icon(Icons.movie, color: Colors.white24, size: 40),
                      ),
                    )
                  : Container(
                      width: cardWidth,
                      height: cardHeight,
                      color: const Color(0xFF1A3528),
                      child: const Icon(Icons.movie, color: Colors.white24, size: 40),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              film.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: const [
          Icon(Icons.movie_outlined, color: Colors.white24, size: 64),
          SizedBox(height: 16),
          Text('No documentaries yet',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 8),
          Text('Be the first to submit one!',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
        ),
      ),
    );
  }

  Widget _themeChips() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length,
        itemBuilder: (_, i) {
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ThemeFilmsScreen(genre: themes[i]['label']!),
                ),
              );
            },
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2E22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF2A4535), width: 0.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(themes[i]['icon']!,
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text(themes[i]['label']!,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _newlyUploadedList(List<Film> films) {
    if (films.isEmpty) {
      return const SizedBox(
        height: 130,
        child: Center(
          child: Text('No uploads yet',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      );
    }
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: films.length,
        itemBuilder: (_, i) {
          final film = films[i];
          return GestureDetector(
            onTap: () => _goToDetail(film),
            child: Container(
              width: 150,
              margin: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    film.thumbnailUrl.isNotEmpty
                        ? Image.network(film.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFF1A3528)))
                        : Container(color: const Color(0xFF1A3528)),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('New',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const Center(
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white70, size: 28)),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(film.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          Text('${film.year} • ${film.genre}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _goToDetail(Film film) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FilmDetailScreen(film: film)));
}