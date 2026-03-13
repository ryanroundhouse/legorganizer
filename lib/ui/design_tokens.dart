import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
}

abstract final class AppRadius {
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));
  static const BorderRadius image = BorderRadius.all(Radius.circular(12));
}

abstract final class AppGrid {
  static const double spacing = 12;
  static const double childAspectRatio = 0.85;
  static const double maxCrossAxisExtent = 220;
}
