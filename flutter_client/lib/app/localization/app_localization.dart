import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const excellentCalendarLocale = Locale('zh', 'CN');

const excellentCalendarSupportedLocales = <Locale>[excellentCalendarLocale];

const excellentCalendarLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
