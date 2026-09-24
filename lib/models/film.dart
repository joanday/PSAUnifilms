import 'package:cloud_firestore/cloud_firestore.dart';

class Film {
  final String id;
  final String title;
  final String director;
  final int year;
  final String genre;
  final List<String> genres;
  final double rating;
  final int ratingCount;
  final int viewCount;
  final String thumbnailUrl;
  final String description;
  final String videoUrl;
  final String uploadedBy;
  final String uploaderName;
  final DateTime? createdAt;
  final String status;
  final String aiSummary;
  final List<String> aiKeywords;
  final bool isOldDocumentary;
  final String visualDescription;
  final List<String> cbvrKeywords;
  final String cbvrSummary;
  final String cbvrStatus;

  const Film({
    required this.id,
    required this.title,
    this.director = '',
    required this.year,
    required this.genre,
    this.genres = const [],
    required this.rating,
    this.ratingCount = 0,
    this.viewCount = 0,
    required this.thumbnailUrl,
    required this.description,
    required this.videoUrl,
    this.uploadedBy = '',
    this.uploaderName = '',
    this.createdAt,
    this.status = 'approved',
    this.aiSummary = '',
    this.aiKeywords = const [],
    this.isOldDocumentary = false,
    this.visualDescription = '',
    this.cbvrKeywords = const [],
    this.cbvrSummary = '',
    this.cbvrStatus = '',
  });

  factory Film.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    List<String> parsedCbvrKeywords = [];
    String parsedCbvrSummary = '';
    if (data['cbvrData'] is Map) {
      if (data['cbvrData']['searchKeywords'] != null) {
        parsedCbvrKeywords =
            List<String>.from(data['cbvrData']['searchKeywords']);
      }
      if (data['cbvrData']['transcriptSummary'] != null) {
        parsedCbvrSummary = data['cbvrData']['transcriptSummary'] as String;
      }
    }

    final String primaryGenre = data['genre'] ?? 'Documentary';
    final List<String> parsedGenres = data['genres'] != null
        ? List<String>.from(data['genres'])
        : [primaryGenre];

    return Film(
      id: doc.id,
      title: data['title'] ?? '',
      director: data['director'] ?? '',
      year: data['year'] != null
          ? (data['year'] is int
              ? data['year']
              : int.tryParse('${data['year']}') ?? 2024)
          : 2024,
      genre: primaryGenre,
      genres: parsedGenres,
      rating: data['rating'] != null ? (data['rating'] as num).toDouble() : 0.0,
      ratingCount: data['ratingCount'] != null
          ? (data['ratingCount'] as num).toInt()
          : 0,
      viewCount:
          data['viewCount'] != null ? (data['viewCount'] as num).toInt() : 0,
      thumbnailUrl: data['thumbnail'] ?? data['thumbnailUrl'] ?? '',
      description: data['description'] ?? '',
      videoUrl: data['videoUrl'] ?? '',
      uploadedBy: data['uploadedBy'] ?? '',
      uploaderName: data['uploaderName'] ?? 'Student',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'approved',
      aiSummary: data['aiSummary'] ?? '',
      aiKeywords: List<String>.from(data['aiKeywords'] ?? []),
      isOldDocumentary: data['isOldDocumentary'] ?? false,
      visualDescription: data['visualDescription'] ?? '',
      cbvrKeywords: parsedCbvrKeywords,
      cbvrSummary: parsedCbvrSummary,
      cbvrStatus: data['cbvrStatus'] ?? '',
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
