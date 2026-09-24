import 'package:flutter/material.dart';
import 'manage_users_screen.dart';
import 'submit_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import '../widgets/user_avatar.dart';

// ─── Theme Constants ──────────────────────────────────────────────────────────

const _bgDark = Color(0xFF0F1A0F);
const _bgCard = Color(0xFF1A2B1A);
const _green = Color(0xFF4CAF50);
const _textPrimary = Color(0xFFE8F5E9);
const _textSecondary = Color(0xFF9E9E9E);
// ✅ NEW: one flat, solid color for every selected nav tab's pill
// background (Watch/Users/Upload/Profile) -- guaranteed identical on all
// of them since it's a plain fill, not a translucent blend.
const _selectedPillColor = Color(0xFF1E3E24);

// ─── Main Screen ──────────────────────────────────────────────────────────────
//
// ✅ SIMPLIFIED: Admins no longer moderate a separate approval queue --
// uploads publish immediately now (see submit_screen.dart), so the old
// Dashboard/Submissions moderation tabs (pending stats, approve/return,
// moderation queue) are gone entirely. Admins now get the exact same
// browsing/watching experience as everyone else via HomeScreen, plus the
// Users and Upload tabs they need that regular viewers don't have.
//
// ✅ NEW: on a wide (desktop/Chrome) window, navigation moves to a
// Netflix-style top bar instead of the bottom tab bar -- easier to reach
// with a mouse and reads as a proper desktop layout instead of a phone UI
// stretched taller. On an actual phone (narrow window, width <= 600) this
// has zero effect: the bottom nav stays exactly as it always was.

class DevcomDashboardScreen extends StatefulWidget {
  const DevcomDashboardScreen({super.key});

  @override
  State<DevcomDashboardScreen> createState() => _DevcomDashboardScreenState();
}

class _DevcomDashboardScreenState extends State<DevcomDashboardScreen> {
  // ✅ CHANGED: was a plain `int _selectedTab` field. Any screen opened via
  // Navigator.push from inside a tab (e.g. Profile > "Edit Documentary
  // Videos", or tapping a film to open Film Detail) used to push a whole
  // new full-screen route that covered EVERYTHING, including this top nav
  // bar -- so the logo/Watch/Users/Upload/Profile bar disappeared the
  // moment you went one level deep anywhere in the app.
  //
  // Fix: the tab content now lives inside its OWN nested Navigator, with
  // this top nav bar sitting outside/above it. Every Navigator.push call
  // anywhere in the app -- in HomeScreen, ProfileScreen, EditDocumentaries
  // Screen, etc. -- automatically targets the NEAREST Navigator ancestor,
  // which is now this nested one instead of the app's root Navigator, so
  // pushed screens only replace the content BELOW the nav bar. The nav bar
  // itself, sitting outside that nested Navigator, now stays on screen no
  // matter how deep the user navigates.
  //
  // _selectedTab is a ValueNotifier (instead of a plain field) so the nav
  // bar and the tab content can each rebuild themselves independently via
  // ValueListenableBuilder, regardless of whether the nested Navigator's
  // own route happens to rebuild.
  final ValueNotifier<int> _selectedTab = ValueNotifier<int>(0);
  final GlobalKey<NavigatorState> _tabNavigatorKey =
      GlobalKey<NavigatorState>();

  void _onNavTap(int i) {
    // If a sub-page was open (e.g. Edit Documentary Videos) and the user
    // taps a different top-level tab, drop back to that tab's own root
    // first -- otherwise switching tabs could leave a stale sub-page
    // sitting on top of the newly selected tab.
    _tabNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    _selectedTab.value = i;
  }

  @override
  void dispose() {
    _selectedTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const ManageUsersScreen(),
      const SubmitScreen(),
      const ProfileScreen(),
    ];

    final isWide = MediaQuery.of(context).size.width > 600;

    final tabNavigator = Navigator(
      key: _tabNavigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _selectedTab,
          builder: (_, index, __) =>
              IndexedStack(index: index, children: screens),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: _bgDark,
      body: isWide
          ? Column(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: _selectedTab,
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
          : ValueListenableBuilder<int>(
              valueListenable: _selectedTab,
              builder: (_, index, __) => _BottomNav(
                selectedIndex: index,
                onTap: _onNavTap,
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

  static const _items = ['Watch', 'Users', 'Upload', 'Profile'];

  // ✅ CHANGED: nav items used to be wrapped in Expanded, so together they
  // always stretched to fill the ENTIRE bar width -- fine back when the
  // bar was capped at 480px, but now that it spans the whole browser
  // window, that same logic spread Watch/Users/Upload out with huge,
  // ever-growing gaps and made the bar look oddly stretched out. Now the
  // items sit compact, right next to the brand, sized to their own text
  // (bigger font per feedback) instead of stretching -- only Profile is
  // pinned to the far right. Wrapped in a horizontal scroll view purely
  // as a safety net so it still can never overflow, even on an unusually
  // narrow "wide" window.
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
              // ✅ CHANGED: was a translucent alpha-blended tint
              // (_green.withValues(alpha: 0.14)) -- same formula on every
              // tab, but a translucent fill can still render slightly
              // differently depending on the box's size/shape. Switched to
              // one flat, solid color instead (no blending involved at
              // all), so Watch/Users/Upload/Profile are now guaranteed
              // pixel-identical when selected, no matter the label length.
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
          // ✅ CHANGED: per feedback, the tabs used to spread evenly across
          // the ENTIRE remaining bar width, which on a wide window pushed
          // ✅ CHANGED: per the mockup reference, the tabs now spread evenly
          // across the entire remaining bar width again -- but this time
          // Profile is included INSIDE this same Expanded/spaceEvenly group
          // (it used to be pinned outside on its own, which is what jammed
          // it against the edge before). With all four tabs sharing one
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
                _pill(3, trailingGap: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Navigation (phone only) ─────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Watch',
                  index: 0,
                  selected: selectedIndex == 0,
                  onTap: onTap),
              _NavItem(
                  icon: Icons.people_outlined,
                  label: 'Users',
                  index: 1,
                  selected: selectedIndex == 1,
                  onTap: onTap),
              _NavItem(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Upload',
                  index: 2,
                  selected: selectedIndex == 2,
                  onTap: onTap),
              // ✅ Profile tab (same ProfileScreen the Viewer uses). Log Out
              // and "My Watchlist" both live inside it, same as they do for
              // everyone else -- keeps this bottom nav focused on the
              // Admin's core job (Watch/Users/Upload) instead of getting
              // crowded with personal-account items.
              _NavItem(
                  icon: Icons.person_outline,
                  label: 'Profile',
                  index: 3,
                  selected: selectedIndex == 3,
                  onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool selected;
  final ValueChanged<int> onTap;

  const _NavItem(
      {required this.icon,
      required this.label,
      required this.index,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _green : _textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
