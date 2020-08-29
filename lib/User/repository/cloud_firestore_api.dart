import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:platzi_trips_app/Place/model/place.dart';
import 'package:platzi_trips_app/Place/ui/widgets/card_image.dart';
import 'package:platzi_trips_app/Place/ui/widgets/card_image_list.dart';
import 'package:platzi_trips_app/User/model/user.dart';
import 'package:platzi_trips_app/User/ui/widgets/profile_place.dart';

class CloudFirestoreAPI {

  final String USERS = "users";
  final String PLACES = "places";

  final Firestore _db = Firestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;


  void updateUserData(user) async{
    DocumentReference ref = _db.collection(USERS).doc(user.uid);
    return await ref.set({
      'uid': user.uid,
      'name': user.name,
      'email': user.email,
      'photoURL': user.photoURL,
      'myPlaces': user.myPlaces,
      'myFavoritePlaces': user.myFavoritePlaces,
      'lastSignIn': DateTime.now()

    },
      //como poner el SetOptions.merge
    );

  }

  Future<void> updatePlaceData(Place place) async {
    CollectionReference refPlaces = _db.collection(PLACES);

    //await _auth.currentUser.then((FirebaseUser user){
    await _auth.currentUser.uid; {

      refPlaces.add({
        'name' : place.name,
        'description': place.description,
        'likes': place.likes,
        'urlImage': place.urlImage,
        'userOwner': _db.doc("$USERS/${userBloc.currentUser.uid}"),//reference
      }).then((DocumentReference dr) {
        dr.get().then((DocumentSnapshot snapshot){
          //ID Place REFERENCIA ARRAY
          DocumentReference refUsers = _db.collection(USERS).doc(userBloc.currentUser.uid);
          refUsers.update({
            'myPlaces' : FieldValue.arrayUnion([_db.doc("$PLACES/${snapshot.id}")])
          });

        });
      });
    };


  }

  List<ProfilePlace> buildMyPlaces(List<DocumentSnapshot> placesListSnapshot){
    List<ProfilePlace> profilePlaces = List<ProfilePlace>();
    placesListSnapshot.forEach((p) {

      profilePlaces.add(ProfilePlace(
        Place(name: p.data()['name'],

            description: p.data()['description'],
            urlImage: p.data()['urlImage'],
            likes: p.data()['likes']

        ),

      ));

    });

    return profilePlaces;


  }

  List<Place> buildPlaces(List<DocumentSnapshot> placesListSnapshot, User user) {
    List<Place> places = List<Place>();

    placesListSnapshot.forEach((p)  {
      Place place = Place(id: p.id, name: p.data()["name"], description: p.data()["description"],
          urlImage: p.data()["urlImage"],likes: p.data()["likes"]
      );
      List usersLikedRefs =  p.data()["usersLiked"];
      place.liked = false;
      usersLikedRefs?.forEach((drUL){
        if(user.uid == drUL.documentID){
          place.liked = true;
        }
      });
      places.add(place);
    });
    return places;
  }

  Future likePlace(Place place, String uid) async {
    await _db.collection(PLACES).doc(place.id).get()
        .then((DocumentSnapshot ds){
       int likes = ds.data()["likes"];

       _db.collection(PLACES).doc(place.id)
           .update({
         'likes': place.liked?likes+1:likes-1,
         'usersLiked':
         place.liked?
         FieldValue.arrayUnion([_db.doc("$USERS/$uid")]):
         FieldValue.arrayRemove([_db.doc("$USERS/$uid")])
       });


    });
  }





}