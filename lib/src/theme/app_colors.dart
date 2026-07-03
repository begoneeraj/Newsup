import 'package:flutter/material.dart';

import '../models/fact_check.dart';

/// Design tokens for Newsup. High-density, forensic/newsroom aesthetic.
class AppColors {
  AppColors._();

  static const Color charcoal = Color(0xFF1C1C1E);
  static const Color forensicBlue = Color(0xFF0C447C);
  static const Color verifiedGreen = Color(0xFF27500A);
  static const Color falseRed = Color(0xFF791F1F);
  static const Color misleadingAmber = Color(0xFF633806);

  static Color statusColor(FactCheckStatus status) {
    switch (status) {
      case FactCheckStatus.verified:
        return verifiedGreen;
      case FactCheckStatus.falseClaim:
        return falseRed;
      case FactCheckStatus.misleading:
        return misleadingAmber;
      case FactCheckStatus.partlyTrue:
        return misleadingAmber;
      case FactCheckStatus.outOfContext:
        return misleadingAmber;
      case FactCheckStatus.satire:
        return forensicBlue;
      case FactCheckStatus.unverified:
        return Colors.grey.shade700;
    }
  }
}
