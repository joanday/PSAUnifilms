
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/firebase_options.dart';

void main() async {
  print('Initializing Firebase...');
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('Firebase initialized. Fetching latest film...');
    final snapshot = await FirebaseFirestore.instance.collection('films').orderBy('createdAt', descending: true).limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      print('Latest Film: \');
      print('AI Summary: \');
      print('AI Keywords: \');
    } else {
      print('No films found.');
    }
  } catch (e) {
    print('Error: \');
  }
}

