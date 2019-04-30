import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:platzi_trips_app/Place/repository/firebase_storage_api.dart';

class FirebaseStorageRepository {

  final _firebaseStorageAPI = FirebaseStorageAPI();

  Future<StorageUploadTask> uploadFile(String path, File image) => _firebaseStorageAPI.uploadFile(path, image);
}