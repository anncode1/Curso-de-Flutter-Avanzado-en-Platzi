import 'package:flutter/material.dart';
import 'profile_place.dart';
import 'place.dart';

class ProfilePlacesList extends StatelessWidget {

  Place place = new Place('Knuckles Mountains Range', 'Hiking. Water fall hunting. Natural bath', 'Scenery & Photography', '123,123,123');
  Place place2 = new Place('Mountains', 'Hiking. Water fall hunting. Natural bath', 'Scenery & Photography', '321,321,321');

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
          top: 10.0,
          left: 20.0,
          right: 20.0,
          bottom: 10.0
      ),
      child: Column(
        children: <Widget>[
          ProfilePlace('assets/img/river.jpeg', place),
          ProfilePlace('assets/img/mountain.jpeg', place2),
        ],
      ),
    );
  }

}