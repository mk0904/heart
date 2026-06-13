import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/firebase_options.dart';
import 'dart:io';

Future<void> main() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final db = FirebaseFirestore.instance;
  
  final snapshot = await db.collection('notifications').orderBy('createdAt', descending: true).limit(1).get();
  if (snapshot.docs.isEmpty) {
    print('No notifications found');
    exit(0);
  }
  
  final doc = snapshot.docs.first;
  final data = doc.data();
  print('Notification ID: ${doc.id}');
  print('Title: ${data['title']}');
  print('Push Status: ${data['pushStatus']}');
  print('Push Failures: ${data['pushFailureCount']}');
  print('Push Successes: ${data['pushSuccessCount']}');
  exit(0);
}
