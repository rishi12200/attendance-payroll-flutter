import 'package:flutter/material.dart';

List<Color> remainingLeavePalette(ColorScheme scheme) => [
  scheme.primary,
  scheme.secondary,
  scheme.tertiary,
  scheme.error,
  scheme.inversePrimary,
  scheme.primaryContainer,
  scheme.secondaryContainer,
  scheme.tertiaryContainer,
];

Color remainingLeaveColor(int index, ColorScheme scheme) {
  final palette = remainingLeavePalette(scheme);
  return palette[index % palette.length];
}
