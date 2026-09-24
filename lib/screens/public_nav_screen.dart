import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'watchlist_screen.dart';
import 'profile_screen.dart';
import '../widgets/user_avatar.dart';

// ✅ NEW: on a wide (desktop/Chrome) window, navigation moves to a
// Netflix-style top bar instead of the bottom tab bar. On an actual phone
// (narrow window, width <= 600) this has zero effect: the bottom nav stays
// exactly as it always was. Mirrors the same pattern used in
// devcom_dashboard_screen.dart for Admin.

const _bgDark = Color(0xFF0F1A0F);
const _bgCard = Color(0xFF1A2B1A);
const _green = Color(0xFF4CAF50);
const _textPrimary = Color(0xFFE8F5E9);
const _textSecondary = Color(0xFF9E9E9E);
// ✅ NEW: one flat, solid color for every selected nav tab's pill
// background (Home/Watchlist/Profile) -- guaranteed identical on all of
// them since it's a plain fill, not a translucent blend.
const _selectedPillColor = Color(0xFF1E3E24);

class PublicNavScreen extends StatefulWidget {
  const PublicNavScreen({super.key});

  @override
  State<PublicNavScreen> createState() => _PublicNavScreenState();
}

class _PublicNavScreenState extends State<PublicNavScreen> {
  // ✅ CHANGED: same fix as devcom_dashboard_screen.dart -- a plain
  // `int _currentIndex` field meant any screen opened via Navigator.push
  // from inside a tab (Film Detail, Browse by Theme, Edit Watchlist entry,
  // etc.) used to cover the ENTIRE screen, including this top nav bar. Now
  // the tab content lives inside its own nested Navigator with the nav bar
  // sitting outside it, so every push anywhere in the app only replaces the
  // content below the bar -- the bar itself always stays visible. See the
  // long comment in devcom_dashboard_screen.dart for the full explanation.
  final ValueNotifier<int> _currentIndex = ValueNotifier<int>(0);
  final GlobalKey<NavigatorState> _tabNavigatorKey =
      GlobalKey<NavigatorState>();

  void _onNavTap(int i) {
    _tabNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    _currentIndex.value = i;
  }

  @override
  void dispose() {
    _currentIndex.dispose();
    super.dispose();
  }

  Widget _buildCurrentScreen(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const WatchlistScreen();
      case 2:
        return const ProfileScreen();
      default:
        return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    final tabNavigator = Navigator(
      key: _tabNavigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _currentIndex,
          builder: (_, index, __) => _buildCurrentScreen(index),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: _bgDark,
      body: isWide
          ? Column(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: _currentIndex,
                  builder: (_, index, __) => _TopNav(
                    selectedIndex: index,
                    onTap: _onNavTap,
                  ),
                ),
                Expanded(child: tabNavigator),
              ],
            )
          : tabNavigator,
      bottomNavigationBar: isWide
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F1A0F),
                border: Border(
                    top: BorderSide(color: Color(0xFF1E3528), width: 0.5)),
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: _currentIndex,
                builder: (_, index, __) => BottomNavigationBar(
                  currentIndex: index,
                  onTap: _onNavTap,
                  backgroundColor: const Color(0xFF0F1A0F),
                  selectedItemColor: const Color(0xFF4CAF50),
                  unselectedItemColor: Colors.white38,
                  type: BottomNavigationBarType.fixed,
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  items: const [
                    BottomNavigationBarItem(
                        icon: Icon(Icons.home_outlined),
                        activeIcon: Icon(Icons.home_rounded),
                        label: 'Home'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.list_outlined),
                        activeIcon: Icon(Icons.list_rounded),
                        label: 'Watchlist'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.person_outline),
                        activeIcon: Icon(Icons.person_rounded),
                        label: 'Profile'),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─── Top Navigation (desktop/Chrome only) ──────────────────────────────────────

class _TopNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _TopNav({required this.selectedIndex, required this.onTap});

  static const _items = ['Home', 'Watchlist', 'Profile'];

  // ✅ CHANGED: nav items used to be wrapped in Expanded, so together they
  // always stretched to fill the ENTIRE bar width -- fine back when the
  // bar was capped at 480px, but now that it spans the whole browser
  // window, that same logic spread Home/Watchlist out with huge, ever-
  // growing gaps and made the bar look oddly stretched out. Now the items
  // sit compact, right next to the brand, sized to their own text (bigger
  // font per feedback) instead of stretching -- only Profile is pinned to
  // the far right. Wrapped in a horizontal scroll view purely as a safety
  // net so it still can never overflow, even on an unusually narrow
  // "wide" window.
  Widget _pill(int i, {bool trailingGap = true}) {
    final selected = selectedIndex == i;
    final label = _items[i];
    final isProfile = i == _items.length - 1;
    return Padding(
      padding: EdgeInsets.only(right: trailingGap ? 100 : 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(i),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              // ✅ CHANGED: matches the same fix in devcom_dashboard_screen
              // .dart -- a flat, solid color instead of a translucent
              // blend, so it's guaranteed pixel-identical on every tab.
              color: selected ? _selectedPillColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(color: _green.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isProfile) ...[
                  // ✅ CHANGED: now shows the actual signed-in user's real
                  // profile picture (or their initials if they haven't set
                  // one) instead of a generic person icon -- same
                  // UserAvatar widget already used elsewhere in the app.
                  // Bigger now (radius 14 instead of 9) per feedback.
                  const UserAvatar(radius: 14, showInitialsFallback: true),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? _green : _textPrimary,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _bgCard,
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // ✅ CHANGED: bigger logo now (44x44 instead of 28x28) per
          // feedback -- uses the actual PSAU logo image (same asset as the
          // Home screen's own app bar) instead of a plain green circle +
          // movie icon.
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                image: AssetImage('assets/images/psaulogo.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // ✅ CHANGED: brought back the "Student Films Showcase App"
          // subtitle underneath the brand name -- it used to live in
          // HomeScreen's own app bar, but that got removed on desktop
          // (duplicate of this nav bar) which accidentally dropped the
          // subtitle entirely. It now lives here instead, permanently
          // visible on every tab, not just Watch.
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PSAUniFilms',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              Text('Student Films Showcase App',
                  style: TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          // ✅ CHANGED: per the mockup reference, the tabs now spread evenly
          // across the entire remaining bar width again -- but this time
          // Profile is included INSIDE this same Expanded/spaceEvenly group
          // (it used to be pinned outside on its own, which is what jammed
          // it against the edge before). With all three tabs sharing one
          // evenly-spaced row, the gaps stay wide and proportional, and
          // Profile lines up naturally with the rest instead of floating
          // apart from them.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _pill(0, trailingGap: false),
                _pill(1, trailingGap: false),
                _pill(2, trailingGap: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
