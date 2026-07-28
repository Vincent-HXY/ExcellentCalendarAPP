import 'package:flutter/material.dart';

abstract final class EventDetailColors {
  static const backgroundStart = Color(0xFFF7FCFD);
  static const backgroundMiddle = Color(0xFFE8F7FA);
  static const backgroundEnd = Color(0xFFF6FCFD);
  static const cardBackground = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF15212B);
  static const secondaryText = Color(0xFF8D989F);
  static const divider = Color(0xFFEDF1F2);
  static const primaryTeal = Color(0xFF38B8C2);
  static const primaryTealDark = Color(0xFF2FAFB9);
  static const primaryTealLight = Color(0xFFDDF3F5);
  static const warningOrange = Color(0xFFF39A18);
  static const warningBackground = Color(0xFFFFF5E5);
  static const disabledBlueGray = Color(0xFFBCCBDB);
  static const disabledGray = Color(0xFFD6DADE);
}

abstract final class EventDetailSpacing {
  static const pageHorizontal = 32.0;
  static const contentMaxWidth = 480.0;
  static const cardPadding = 14.0;
  static const sectionTop = 16.0;
  static const sectionToCard = 8.0;
}

abstract final class EventDetailSizes {
  static const cardRadius = 12.0;
  static const topBarHeight = 56.0;
  static const summaryHeight = 76.0;
  static const scheduleRowHeight = 39.0;
  static const allDayRowHeight = 42.0;
  static const actionBarContentHeight = 62.0;
}

abstract final class EventDetailTextStyles {
  static const topBarTitle = TextStyle(
    color: EventDetailColors.primaryText,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  static const summaryTitle = TextStyle(
    color: EventDetailColors.primaryText,
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );

  static const summaryDescription = TextStyle(
    color: EventDetailColors.secondaryText,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  static const sectionTitle = TextStyle(
    color: EventDetailColors.primaryText,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const timelineLabel = TextStyle(
    color: EventDetailColors.secondaryText,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const timelineValue = TextStyle(
    color: EventDetailColors.primaryText,
    fontSize: 15.5,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static const note = TextStyle(
    color: EventDetailColors.primaryText,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  static const metaLabel = TextStyle(
    color: EventDetailColors.secondaryText,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const metaValue = TextStyle(
    color: EventDetailColors.primaryText,
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}

BoxDecoration eventDetailCardDecoration() {
  return BoxDecoration(
    color: EventDetailColors.cardBackground,
    borderRadius: BorderRadius.circular(EventDetailSizes.cardRadius),
    boxShadow: const [
      BoxShadow(color: Color(0x0A6F8790), blurRadius: 16, offset: Offset(0, 5)),
    ],
  );
}
