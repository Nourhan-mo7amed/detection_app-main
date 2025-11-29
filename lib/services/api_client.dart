
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';

class ApiClient {
  final http.Client _client;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  Future<void> sendSingleProduct({
    required String productId,
    required int maxDefects,
    required String finalStatus,
  }) async {
    final payload = {
      "product_id": productId,
      "session_id": AppConfig.sessionId,
      "status": finalStatus,
      "max_defects": maxDefects,
      "timestamp": DateTime.now().toIso8601String(),
      "productionline_id": AppConfig.productionLineId,
      "companyId": AppConfig.companyId,
    };

    try {
      await _client.post(
        Uri.parse(AppConfig.apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {
      // تقدر تحط لوج هنا لو حابب
    }
  }
}
