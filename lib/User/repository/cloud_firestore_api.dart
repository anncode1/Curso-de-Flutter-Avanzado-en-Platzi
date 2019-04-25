import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:platzi_trips_app/User/model/user.dart';

class CloudFirestoreAPI {

  final String USERS = "users";
  final String PLACE = "places";

  final Firestore _db = Firestore.instance;

  void updateUserData(User user) async{
    DocumentReference ref = _db.collection(USERS).document(user.uid);
    return ref.setData({
      'uid': user.uid,
      'name': user.name,
      'email': user.email,
      'photoURL': user.photoURL,
      'myPlaces': user.myPlaces,
      'myFavoritePlaces': user.myFavoritePlaces,
      'lastSignIn': DateTime.now()

    }, merge: true);

  }

}