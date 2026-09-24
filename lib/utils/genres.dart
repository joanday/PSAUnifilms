import 'package:flutter/material.dart';

// ─── Single source of truth for the app's documentary genres/themes ────────
//
// Used by both the Home screen's "Browse by Theme" chips and the Submit
// Film upload form's genre picker, so the exact same icon + label always
// means the same genre everywhere in the app -- one uniform, professional
// icon set instead of mismatched colorful emoji.

class GenreInfo {
  final String label;
  final IconData icon;
  const GenreInfo({required this.label, required this.icon});
}

const List<GenreInfo> kGenres = [
  GenreInfo(label: 'Agriculture', icon: Icons.agriculture_rounded),
  GenreInfo(label: 'Culture', icon: Icons.theater_comedy_rounded),
  GenreInfo(label: 'Environment', icon: Icons.eco_rounded),
  GenreInfo(label: 'Education', icon: Icons.school_rounded),
  GenreInfo(label: 'Community', icon: Icons.groups_rounded),
  GenreInfo(label: 'Media & Development', icon: Icons.laptop_mac_rounded),
];
