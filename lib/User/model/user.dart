import 'package:flutter/material.dart';

class User {
  final String name;
  final String email;
  final String photoURL;

  //myFavoritePlaces
  //myPlaces

  User({
    Key key,
    @required this.name,
    @required this.email,
    @required this.photoURL,
  });

}