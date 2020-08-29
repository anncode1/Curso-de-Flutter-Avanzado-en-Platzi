import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:generic_bloc_provider/generic_bloc_provider.dart';
import 'package:platzi_trips_app/Place/ui/screens/add_place_screen.dart';
import 'package:platzi_trips_app/User/bloc/bloc_user.dart';
import 'circle_button.dart';
import 'package:image_picker/image_picker.dart';

class ButtonsBar extends StatefulWidget {
  @override
  _ButtonsBarState createState() => _ButtonsBarState();
}

class _ButtonsBarState extends State<ButtonsBar> {
  UserBloc userBloc;
  final ImagePicker _picker = ImagePicker();
  @override
  Widget build(BuildContext context) {
    userBloc = BlocProvider.of(context);

    return Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 0.0,
            vertical: 10.0
        ),
        child: Row(
          children: <Widget>[
            //Cambiar la contraseña
            CircleButton(true, Icons.vpn_key, 20.0, Color.fromRGBO(255, 255, 255, 0.6)
                , () => {}),
            //Añadiremos un nuevo lugar
            CircleButton(false, Icons.add, 40.0, Color.fromRGBO(255, 255, 255, 1),
              () async {

                /*ImagePicker.pickImage(source: ImageSource.camera)
                    .then((File image) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (BuildContext context) => AddPlaceScreen(image: image)));
                }).catchError((onError) => print(onError));
                */
                try {
                  final pickedFile = await _picker.getImage(
                      source: ImageSource.camera);
                  setState(() {
                    File pickedFile;
                    Navigator.push(context,
                        MaterialPageRoute(builder: (BuildContext context) =>
                            AddPlaceScreen(image: pickedFile)));
                  });
                }
                catch (e) {
                  setState(() {
                    print(e);
                  });
                }
              }),


            //Cerrar Sesión
            CircleButton(true, Icons.exit_to_app, 20.0, Color.fromRGBO(255, 255, 255, 0.6),
                    () => {
                      userBloc.signOut()
                }),
          ],
        )
    );
  }
}