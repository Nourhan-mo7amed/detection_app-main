// lib/config.dart
import 'package:uuid/uuid.dart';

class AppConfig {
  // thresholds
  static const double cartonConf = 0.5;
  static const double defectConf = 0.40;

  // expand box ratio قبل الكروب للديفكت
  static const double expandRatio = 0.05;

  // API config (نفس اللي في config.py تقريباً)
  static const String apiUrl =
      'https://chainly.azurewebsites.net/api/ProductionLines/sessions';
  static const int productionLineId = 1;
  static const int companyId = 90;

  // Session ID مرة واحدة لكل تشغيل
  static final String sessionId = const Uuid().v4().replaceAll('-', '');
}
