import 'package:flutter/material.dart';

const remainingLeavePalette = <Color>[
  Color(0xff1565c0),
  Color(0xff00897b),
  Color(0xffef6c00),
  Color(0xff7b1fa2),
  Color(0xffc62828),
  Color(0xff558b2f),
  Color(0xffad1457),
  Color(0xff546e7a),
];

Color remainingLeaveColor(int index) =>
    remainingLeavePalette[index % remainingLeavePalette.length];
