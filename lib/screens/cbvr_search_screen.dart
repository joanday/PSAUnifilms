import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/film.dart';
import 'film_detail_screen.dart';

class CbvrSearchScreen extends StatefulWidget {
  const CbvrSearchScreen({super.key});

  @override
  State<CbvrSearchScreen> createState() => _CbvrSearchScreenState();
}

class _CbvrSearchScreenState extends State<CbvrSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Film> _searchResults = [];
  String? _errorMessage;

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('searchFilmsCBVR');
      final result = await callable.call({'query': query});
      
      final List<dynamic> data = result.data['results'] ?? [];
      
      setState(() {
        _searchResults = data.map((json) {
          return Film(
            id: json['id'],
            title: json['title'] ?? '',
            genre: json['genre'] ?? '',
            year: json['year'] ?? 0,
            rating: (json['rating'] ?? 0.0).toDouble(),
            description: json['description'] ?? '',
            videoUrl: json['videoUrl'] ?? '',
            thumbnailUrl: json['thumbnailUrl'] ?? '',
            uploadedBy: json['uploadedBy'] ?? '',
            uploaderName: json['uploaderName'] ?? '',
            status: json['status'] ?? 'pending',
          );
        }).toList();
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to perform semantic search: $e";
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CBVR AI Search', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[900],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. "scenes showing traditional farming"',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[850],
                prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Colors.amber),
                  onPressed: _performSearch,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _performSearch(),
            ),
          ),
          if (_isSearching)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 16),
                    Text(
                      'AI is analyzing your semantic query...',
                      style: TextStyle(color: Colors.white70),
                    )
                  ],
                ),
              ),
            )
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else if (_searchResults.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Describe a scene, theme, or object to retrieve documentaries.',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final film = _searchResults[index];
                  return Card(
                    color: Colors.grey[850],
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FilmDetailScreen(film: film),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Image.network(
                            film.thumbnailUrl,
                            width: 120,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => Container(
                              width: 120,
                              height: 90,
                              color: Colors.grey,
                              child: const Icon(Icons.movie, color: Colors.white54),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    film.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    film.genre,
                                    style: TextStyle(
                                      color: Colors.blueAccent[100],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    film.description,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
