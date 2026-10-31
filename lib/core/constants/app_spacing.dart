import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  static const double buttonHeight = 48.0;
  static const double buttonHeightCompact = 36.0;
  static const double buttonRadius = 8.0;
  static const double cardRadius = 12.0;
  static const double modalRadius = 16.0;

  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;

  static const double screenMargin = 16.0;
  static const EdgeInsets screenPadding = EdgeInsets.all(screenMargin);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets cardMargin = EdgeInsets.only(bottom: md);
  static const EdgeInsets sheetPadding = EdgeInsets.fromLTRB(xxl, lg, xxl, xxxl);
  static const EdgeInsets dialogPadding = EdgeInsets.all(xxl);
}
