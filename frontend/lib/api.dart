import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class DatasetApi {
  final String baseUrl;
  final String token;
  final http.Client client;
  DatasetApi({required String baseUrl, this.token = '', http.Client? client})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      client = client ?? http.Client();
  Map<String, String> get headers => {
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  Uri uri(String path) => Uri.parse('$baseUrl$path');
  Future<Json> request(String path, {Json? body}) async {
    try {
      final response =
          await (body == null
                  ? client.get(uri(path), headers: headers)
                  : client.post(
                      uri(path),
                      headers: {...headers, 'Content-Type': 'application/json'},
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(minutes: 6));
      return decode(response);
    } on http.ClientException {
      throw ApiException(
        'ارتباط با سرور برقرار نشد. آدرس، اجرای API و مجوز مرورگر را بررسی کنید.',
      );
    } on TimeoutException {
      throw ApiException(
        'زمان انتظار تمام شد. وضعیت کار را در سرور بررسی کنید.',
      );
    }
  }

  Json decode(http.Response response) {
    dynamic value;
    try {
      value = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException('پاسخ نامعتبر از سرور (${response.statusCode})');
    }
    if (response.statusCode >= 400) {
      final error = value is Map ? value['error'] : null;
      throw ApiException(
        error is Map
            ? '${error['message']} (${error['code']})'
            : 'خطای سرور: ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(value as Map);
  }

  Future<Json> upload(String name, Uint8List bytes) async {
    try {
      final request = http.MultipartRequest('POST', uri('/datasets'))
        ..headers.addAll(headers)
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: name),
        );
      return decode(
        await http.Response.fromStream(
          await client.send(request).timeout(const Duration(minutes: 2)),
        ),
      );
    } on http.ClientException {
      throw ApiException(
        'بارگذاری انجام نشد؛ اتصال و مجوز مرورگر را بررسی کنید.',
      );
    }
  }

  Future<Json> tool(String name, Json arguments) =>
      request('/tools/$name', body: {'arguments': arguments});
  Future<Json> waitForJob(
    String id, {
    void Function(Json)? onUpdate,
    Duration interval = const Duration(milliseconds: 800),
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 35));
    while (DateTime.now().isBefore(deadline)) {
      final job = await request('/jobs/$id');
      onUpdate?.call(job);
      if (job['status'] == 'succeeded') {
        return Map<String, dynamic>.from(job['result'] as Map);
      }
      if (job['status'] == 'failed' || job['status'] == 'cancelled') {
        throw ApiException(
          job['status'] == 'cancelled'
              ? 'کار لغو شد.'
              : '${job['error']?['message'] ?? 'کار ناموفق بود'}',
        );
      }
      await Future<void>.delayed(interval);
    }
    throw ApiException('زمان انتظار تمام شد؛ شناسهٔ کار: $id');
  }

  Future<Uint8List> download(String path) async {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        Uri.parse(path).hasScheme) {
      throw ApiException('مسیر دریافت فایل نامعتبر است.');
    }
    final response = await client
        .get(uri(path), headers: headers)
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      decode(response);
    }
    return response.bodyBytes;
  }

  void close() => client.close();
}
