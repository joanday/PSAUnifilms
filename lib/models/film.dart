import 'package:cloud_firestore/cloud_firestore.dart';

class Film {
  final String id;
  final String title;
  final String director;
  final int year;
  final String genre;
  final double rating;
  final String thumbnailUrl;
  final String description;
  final String videoUrl;
  final String? youtubeId; // ← added
  final String uploadedBy;
  final String uploaderName;
  final DateTime? createdAt;
  final String status;
  final String aiSummary;
  final List<String> aiKeywords;

  const Film({
    required this.id,
    required this.title,
    this.director = '',
    required this.year,
    required this.genre,
    required this.rating,
    required this.thumbnailUrl,
    required this.description,
    required this.videoUrl,
    this.youtubeId, // ← added
    this.uploadedBy = '',
    this.uploaderName = '',
    this.createdAt,
    this.status = 'approved',
    this.aiSummary = '',
    this.aiKeywords = const [],
  });

  factory Film.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Film(
      id: doc.id,
      title: data['title'] ?? '',
      director: data['director'] ?? '',
      year: data['year'] != null
          ? (data['year'] is int
              ? data['year']
              : int.tryParse('${data['year']}') ?? 2024)
          : 2024,
      genre: data['genre'] ?? 'Documentary',
      rating: data['rating'] != null ? (data['rating'] as num).toDouble() : 0.0,
      thumbnailUrl: data['thumbnail'] ?? data['thumbnailUrl'] ?? '',
      description: data['description'] ?? '',
      videoUrl: data['videoUrl'] ?? '',
      youtubeId: data['youtubeId'], // ← added
      uploadedBy: data['uploadedBy'] ?? '',
      uploaderName: data['uploaderName'] ?? 'Student',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'approved',
      aiSummary: data['aiSummary'] ?? '',
      aiKeywords: List<String>.from(data['aiKeywords'] ?? []),
    );
  }
}

const List<String> filmThemes = [
  'All',
  'Agriculture',
  'Culture',
  'Environment',
  'Education',
  'Community',
  'Drama',
  'Romance',
  'Thriller',
  'Documentary',
  'Comedy',
  'Short Film',
];
