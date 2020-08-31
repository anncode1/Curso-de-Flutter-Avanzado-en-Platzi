import 'package:flutter/material.dart';
import 'package:platzi_trips_app/User/model/user.dart';

class UserInfo extends StatelessWidget {

  Usuario user;

  

  UserInfo(@required this.user);

  @override
  Widget build(BuildContext context) {

    final userPhoto = Container(
      width: 80.0,
      height: 80.0,
      margin: EdgeInsets.only(
          top: 5,
          right: 20.0,
          bottom: 15.0
      ),
      decoration: BoxDecoration(
          border: Border.all(
              color: Colors.white,
              width: 2.0,
              style: BorderStyle.solid
          ),
          shape: BoxShape.circle,
          image: DecorationImage(
              fit: BoxFit.cover,
              //image: AssetImage(user.photoURL)
            image: NetworkImage(user.photoURL)
          )
      ),
    );

    final userInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
            margin: EdgeInsets.only(
                bottom: 5.0
            ),
            child: Text(
                user.name,
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'Lato',
                )
            )
        ),
        Text(
            user.email,
            style: TextStyle(
                fontSize: 15.0,
                color: Colors.white54,
                fontFamily: 'Lato'
            )
        ),
      ],
    );

    return Container(
      margin: EdgeInsets.symmetric(
          vertical: 0.0,
          horizontal: 0.0
      ),
      child: Column(
        children: <Widget>[
          userPhoto,
          userInfo
        ],
      ),
    );
  }

}