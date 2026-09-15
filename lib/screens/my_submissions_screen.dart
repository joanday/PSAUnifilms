import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/film.dart';
import '../theme/app_theme.dart';
import 'film_detail_screen.dart';

class MySubmissionsScreen extends StatelessWidget {
  const MySubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F17),
        title: const Text('My Submissions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: uid.isEmpty 
          ? const Center(child: Text('Not logged in', style: TextStyle(color: Colors.white)))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('films')
                  .where('uploadedBy', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.greenPrime));
                }
                
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('You have no submissions yet.', 
                        style: TextStyle(color: AppTheme.textMuted)),
                  );
                }

                final films = snapshot.data!.docs.map((doc) => Film.fromFirestore(doc)).toList();
                
                // Sort locally to avoid needing a custom composite index in Firestore
                films.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));

                final published = films.where((f) => f.status == 'approved').toList();
                final pending = films.where((f) => f.status == 'pending').toList();
                final returned = films.where((f) => f.status == 'returned').toList();

                if (published.isEmpty && pending.isEmpty && returned.isEmpty) {
                  return const Center(
                    child: Text('You have no submissions yet.', 
                        style: TextStyle(color: AppTheme.textMuted)),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (published.isNotEmpty) _buildFilmList(context, 'Published', published, const Color(0xFF4CAF50), 'Published', true),
                    if (pending.isNotEmpty) _buildFilmList(context, 'Pending Review', pending, const Color(0xFFFF8F00), 'Under Review', false),
                    if (returned.isNotEmpty) _buildFilmList(context, 'Needs Revision', returned, const Color(0xFFE53935), 'Returned by Officer', false),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildFilmList(BuildContext context, String title, List<Film> films, Color color, String subtitle, bool isApproved) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
          child: Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: films.length,
            itemBuilder: (context, index) {
              final film = films[index];
              
              // Format the date locally
              String formattedDate = '';
              if (film.createdAt != null) {
                final d = film.createdAt!;
                final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                final monthStr = months[d.month - 1];
                final ampm = d.hour >= 12 ? 'PM' : 'AM';
                final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
                final minute = d.minute.toString().padLeft(2, '0');
                formattedDate = '$monthStr ${d.day}, ${d.year} $hour:$minute $ampm';
              }

              return GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FilmDetailScreen(film: film)));
                },
                child: Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                        child: SizedBox(
                          height: 90,
                          width: double.infinity,
                          child: film.thumbnailUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: film.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[900],
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.movie_creation_outlined, color: Colors.white54, size: 24),
                                          SizedBox(height: 4),
                                          Text('Processing...', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey[900],
                                    child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey[900],
                                  child: const Center(
                                    child: Icon(Icons.movie, color: Colors.white54),
                                  ),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              film.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  isApproved ? Icons.check_circle_outline : (film.status == 'returned' ? Icons.error_outline : Icons.access_time), 
                                  color: color, 
                                  size: 12
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: color, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
