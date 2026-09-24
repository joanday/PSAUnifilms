import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/film.dart';
import '../services/cbvr_service.dart';
import '../utils/genres.dart';
import '../widgets/cbvr_result_card.dart';
import '../widgets/showcase_banner.dart';
import '../widgets/user_avatar.dart';
import 'film_detail_screen.dart';
import 'search_screen.dart';
import 'theme_films_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Smart Search (CBVR) state ───────────────────────────────────
  bool _cbvrLoading = false;
  String? _cbvrError;
  List<CbvrResult> _cbvrResults = [];
  String _lastCbvrQuery = '';
  Timer? _debounce;
  // ───────────────────────────────────────────────────────────────

  // ✅ CHANGED: was a list of colorful, mismatched emoji (🌾🏛️🌿📚🤝💻) --
  // now uses the shared, uniform icon set from utils/genres.dart so these
  // chips look professional/consistent, and match the icons used on the
  // Submit Film genre picker exactly.
  final List<GenreInfo> themes = kGenres;

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
      MaterialPageRoute(
          builder: (_) =>
              SearchScreen(initialGenre: genre, isViewAllMode: true)),
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
    // ✅ NEW: on desktop, the top nav bar (devcom_dashboard_screen.dart /
    // public_nav_screen.dart) already shows the PSAUniFilms logo + name and
    // the profile avatar, so this screen's own branded app bar below it was
    // just a duplicate of the same thing. It's now skipped entirely on
    // wide screens -- phone is untouched, still shows it exactly as before.
    final isWide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      // ✅ CHANGED: was 0xFF0D1F17 -- a slightly different dark green shade
      // than manage_users_screen.dart's 0xFF0F1A0F. Now matches it exactly
      // so Watch/Users/Upload/Profile all share the exact same page
      // background instead of subtly different tints.
      backgroundColor: const Color(0xFF0F1A0F),
      body: StreamBuilder<List<Film>>(
        stream: _filmsStream,
        builder: (context, snapshot) {
          final allFilms = snapshot.data ?? [];
          final films = _filterFilms(allFilms);

          final now = DateTime.now();
          final currentMonthFilms = allFilms
              .where((f) =>
                  f.createdAt != null &&
                  f.createdAt!.month == now.month &&
                  f.createdAt!.year == now.year)
              .toList();

          final featured = currentMonthFilms.isNotEmpty
              ? currentMonthFilms.first
              : (allFilms.isNotEmpty ? allFilms.first : null);

          final sevenDaysAgo = now.subtract(const Duration(days: 7));
          final newlyUploaded = allFilms
              .where((f) =>
                  f.createdAt != null &&
                  f.createdAt!.isAfter(sevenDaysAgo) &&
                  !f.isOldDocumentary)
              .take(5)
              .toList();

          return SafeArea(
              child: CustomScrollView(
            slivers: [
              // App Bar -- phone only now (see isWide comment above).
              if (!isWide)
                SliverAppBar(
                  backgroundColor: const Color(0xFF0F1A0F),
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
                  // ✅ CHANGED: on desktop, the app bar that used to sit
                  // above this (with its own height/padding) is gone now
                  // (see isWide check above), so the search bar was left
                  // stuck right against the nav bar with zero breathing
                  // room. Added top padding back, just for isWide. Phone
                  // is untouched -- still has its own app bar above this.
                  padding: EdgeInsets.fromLTRB(16, isWide ? 24 : 0, 16, 0),
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
                                          icon: const Icon(Icons.close,
                                              color: Colors.white54, size: 18),
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
                                  if (_debounce?.isActive ?? false)
                                    _debounce!.cancel();
                                  if (value.trim().isEmpty) {
                                    setState(() {
                                      _cbvrResults = [];
                                      _lastCbvrQuery = '';
                                      _cbvrLoading = false;
                                    });
                                    return;
                                  }
                                  _debounce = Timer(
                                      const Duration(milliseconds: 800), () {
                                    if (_searchQuery.trim().isNotEmpty) {
                                      _runSmartSearch(allFilms);
                                    }
                                  });
                                },
                                onSubmitted: (_) {
                                  if (_debounce?.isActive ?? false)
                                    _debounce!.cancel();
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

                      // Loading
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(
                                color: Color(0xFF4CAF50)),
                          ),
                        )

                      // ── Search results ────────────────────────────
                      else if (_searchQuery.isNotEmpty)
                        ...() {
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
                                          color: Color(0xFF4CAF50),
                                          strokeWidth: 3),
                                      SizedBox(height: 14),
                                      Text('Analyzing with AI...',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 13)),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
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
                            // ✅ CHANGED: these result rows used to stretch to
                            // the full browser width on desktop (the section
                            // they live in has no width cap) -- now capped
                            // and centered at the same 640 max width used
                            // elsewhere in the app. Phone is untouched.
                            widgets.addAll(films.map((film) => Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 640),
                                    child: _searchResultCard(film),
                                  ),
                                )));
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
                                            color: Colors.white54,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              final filmMap = {
                                for (final f in allFilms) f.id: f
                              };
                              // ✅ CHANGED: same width fix as the local
                              // results above -- capped and centered at 640
                              // instead of stretching full browser width.
                              widgets.addAll(uniqueCbvr.map((r) {
                                final film = filmMap[r.filmId];
                                if (film == null)
                                  return const SizedBox.shrink();
                                return Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 640),
                                    child: CbvrResultCard(
                                      film: film,
                                      result: r,
                                      animationIndex: _cbvrResults.indexOf(r),
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                FilmDetailScreen(film: film)),
                                      ),
                                    ),
                                  ),
                                );
                              }));
                            } else if (films.isEmpty) {
                              widgets.add(
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.auto_awesome,
                                            color: Colors.white38, size: 40),
                                        const SizedBox(height: 12),
                                        Text(
                                            'No films matched "$_lastCbvrQuery"',
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                          } else if (films.isEmpty &&
                              !_cbvrLoading &&
                              _lastCbvrQuery.isEmpty) {
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
                            children: [
                              const Text('Monthly Showcase',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // ✅ CHANGED: on desktop this used to stretch to
                          // whatever height its internal aspect ratio
                          // worked out to at full browser width, which on
                          // a wide window made it enormous (nearly the
                          // whole screen tall). Now sized the same way as
                          // the video preview on Submit Film -- capped at
                          // the same 640 max width, proper 16:9 aspect
                          // ratio (not a fixed pixel height), so it reads
                          // as a normal video box instead of a giant
                          // letterboxed strip. Phone is untouched.
                          isWide
                              // ✅ CHANGED: was left-aligned (a ConstrainedBox
                              // on its own just hugs the left edge inside a
                              // Column) -- wrapped in Center now so it sits
                              // in the middle of the page like the mockup,
                              // instead of stuck on the left side.
                              ? Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 640),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: ShowcaseBanner(
                                          films: currentMonthFilms,
                                          onTap: (film) => _goToDetail(film),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : ShowcaseBanner(
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
                                      color: Color(0xFF4CAF50), fontSize: 12)),
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
                          child: LayoutBuilder(
                            builder: (context, gridConstraints) {
                              // ✅ CHANGED: gap matches the reference mockup
                              // exactly (measured directly from the mockup
                              // image): 30px on desktop.
                              final isWideGrid =
                                  MediaQuery.of(context).size.width > 600;
                              // ✅ CHANGED: per feedback, cards inside each
                              // row need to stay LEFT-aligned (so a lone
                              // leftover card on the final row sits on the
                              // left, not floating in the middle) while the
                              // grid as a WHOLE still needs balanced
                              // left/right margins (not all the leftover
                              // space piling up on the right only). Plain
                              // WrapAlignment can't do both at once, so
                              // instead: figure out exactly how many
                              // columns actually fit, size a box to exactly
                              // that many columns' width, and center THAT
                              // box -- cards inside it still start flush
                              // left against the box's own left edge.
                              final spacing = isWideGrid ? 30.0 : 16.0;
                              final cardWidth = isWideGrid
                                  ? 250.0
                                  : (gridConstraints.maxWidth - 16) / 2;
                              final rawColumns =
                                  ((gridConstraints.maxWidth + spacing) /
                                          (cardWidth + spacing))
                                      .floor();
                              final columns = rawColumns < 1 ? 1 : rawColumns;
                              final contentWidth =
                                  columns * cardWidth + (columns - 1) * spacing;
                              return Center(
                                child: SizedBox(
                                  width: contentWidth,
                                  child: Wrap(
                                    spacing: spacing,
                                    runSpacing: isWideGrid ? 30 : 20,
                                    alignment: WrapAlignment.start,
                                    children: allFilms
                                        .map((film) => _portraitFilmCard(film,
                                            context, gridConstraints.maxWidth))
                                        .toList(),
                                  ),
                                ),
                              );
                            },
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
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
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
        child:
            const Icon(Icons.movie_outlined, color: Colors.white24, size: 28),
      );

  Widget _portraitFilmCard(
      Film film, BuildContext context, double availableWidth) {
    // ✅ CHANGED: this used to always size cards for exactly 2 per row,
    // based on the full device/browser width -- fine on a phone, but on a
    // wide desktop window (now that the app uses the full browser width
    // instead of a fixed 480px frame) that made each card balloon up to
    // ~700px, just 2 huge cards filling the whole row. Now: on a phone it
    // still sizes for exactly 2 per row (identical math as before, just
    // driven by the grid's own actual available width instead of the raw
    // device width, which comes to the same number). On a wide/desktop
    // screen it instead targets a fixed, comfortable card width and lets
    // Wrap fit as many columns as the space allows -- a normal multi-
    // column streaming grid instead of 2 giant cards.
    final isWide = MediaQuery.of(context).size.width > 600;
    // ✅ CHANGED: on desktop this now matches the reference mockup exactly
    // (measured directly from the mockup image) -- a 250-wide LANDSCAPE
    // video-thumbnail card (like Newly Uploaded), not the tall 2:3 movie-
    // poster card. Phone keeps the original portrait 2:3 poster card,
    // untouched.
    final cardWidth = isWide ? 250.0 : (availableWidth - 16) / 2;
    final cardHeight = isWide ? cardWidth * 0.68 : cardWidth * 1.5;

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
                        child: const Icon(Icons.movie,
                            color: Colors.white24, size: 40),
                      ),
                    )
                  : Container(
                      width: cardWidth,
                      height: cardHeight,
                      color: const Color(0xFF1A3528),
                      child: const Icon(Icons.movie,
                          color: Colors.white24, size: 40),
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

  Widget _themeChip(GenreInfo theme,
      {double width = 80,
      double verticalPadding = 10,
      double iconSize = 24,
      double labelFontSize = 10}) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ThemeFilmsScreen(genre: theme.label),
          ),
        );
      },
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2E22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A4535), width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ✅ CHANGED: was a raw emoji Text() -- now a uniform Material
            // icon so all 6 chips share the exact same visual style
            // (weight, color, alignment) instead of looking like mismatched
            // stickers.
            Icon(theme.icon, size: iconSize, color: const Color(0xFF4CAF50)),
            const SizedBox(height: 4),
            Text(theme.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _themeChips() {
    // ✅ CHANGED: on a phone this stays exactly as it was -- a horizontal
    // scrolling row of small chips. On wide/desktop, chips are now sized
    // and spaced to match the reference mockup exactly (measured directly
    // from the mockup image): ~250 wide, ~108 tall, bigger icon/label,
    // with a ~22px gap between them -- instead of the smaller, tighter
    // chips used before.
    final isWide = MediaQuery.of(context).size.width > 600;
    if (isWide) {
      // ✅ CHANGED: forced onto a single line now (per feedback) instead of
      // wrapping into multiple rows. Chip width is computed from the
      // actual available width so all 6 always fit exactly on one line --
      // capped at 250 (the mockup size) so they don't balloon on a huge
      // monitor, with a small SingleChildScrollView safety net in case an
      // unusually narrow "wide" window can't fit even the minimum size.
      const gap = 22.0;
      return LayoutBuilder(
        builder: (context, constraints) {
          final totalGap = gap * (themes.length - 1);
          final chipWidth = ((constraints.maxWidth - totalGap) / themes.length)
              .clamp(90.0, 250.0);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < themes.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  _themeChip(
                    themes[i],
                    width: chipWidth,
                    verticalPadding: 28,
                    iconSize: 32,
                    labelFontSize: 13,
                  ),
                ],
              ],
            ),
          );
        },
      );
    }
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _themeChip(themes[i]),
        ),
      ),
    );
  }

  Widget _newlyUploadedCard(Film film,
      {double width = 150, double height = 130}) {
    return GestureDetector(
      onTap: () => _goToDetail(film),
      child: SizedBox(
        width: width,
        height: height,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    // ✅ NEW: views weren't shown here at all before --
                    // added next to year/genre, same as the other film
                    // cards across the app (Browse by Theme, Search).
                    Row(
                      children: [
                        Expanded(
                          child: Text('${film.year} • ${film.genre}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 10)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.visibility_outlined,
                            color: Colors.white54, size: 10),
                        const SizedBox(width: 2),
                        Text('${film.viewCount}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    // ✅ CHANGED: same reasoning as _themeChips -- phone keeps the original
    // horizontal-scrolling row untouched. On a wide/desktop window this
    // now wraps into evenly-spaced rows instead of a short scrollable
    // strip stuck on the left with empty space next to it.
    final isWide = MediaQuery.of(context).size.width > 600;
    if (isWide) {
      // ✅ CHANGED: sized and spaced to match the reference mockup exactly
      // (measured directly from the mockup image): 265x216 cards with a
      // 30px gap between them. Same balanced-margins fix as the "All
      // Documentaries" grid above -- cards stay left-aligned within each
      // row, but the whole block is centered so a half-empty last row
      // doesn't leave all its leftover space on the right only.
      return LayoutBuilder(
        builder: (context, rowConstraints) {
          const cardWidth = 265.0;
          const spacing = 30.0;
          final rawColumns =
              ((rowConstraints.maxWidth + spacing) / (cardWidth + spacing))
                  .floor();
          final columns = rawColumns < 1 ? 1 : rawColumns;
          final contentWidth = columns * cardWidth + (columns - 1) * spacing;
          return Center(
            child: SizedBox(
              width: contentWidth,
              child: Wrap(
                spacing: spacing,
                runSpacing: 30,
                alignment: WrapAlignment.start,
                children: films
                    .map((f) => _newlyUploadedCard(f, width: 265, height: 216))
                    .toList(),
              ),
            ),
          );
        },
      );
    }
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: films.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _newlyUploadedCard(films[i]),
        ),
      ),
    );
  }

  void _goToDetail(Film film) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => FilmDetailScreen(film: film)));
}
