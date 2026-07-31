import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'API_BASE_URL',
                  defaultValue: 'http://10.0.2.2:8000',
                ))
            .replaceAll(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  Future<List<ContentItem>> extractContents(List<File> images) async {
    if (images.isEmpty) throw ApiException('이미지를 한 장 이상 선택해 주세요.');
    final request =
        http.MultipartRequest('POST', Uri.parse('$_baseUrl/contents/extract'));
    for (final image in images) {
      request.files.add(await http.MultipartFile.fromPath(
        'images',
        image.path,
        contentType: _imageContentType(image.path),
      ));
    }
    final streamed = await request.send().timeout(const Duration(seconds: 70));
    final response = await http.Response.fromStream(streamed);
    final json = _decode(response);
    return (json['items'] as List)
        .map((value) => ContentItem.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  MediaType _imageContentType(String path) {
    final extension = path.toLowerCase().split('.').last;
    return switch (extension) {
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      _ => MediaType('application', 'octet-stream'),
    };
  }

  Future<Schedule> generate(LocalPlanDraft draft) =>
      _schedule('/schedules/generate', draft.toRequestJson());

  Future<Schedule> replan(LocalPlan plan) => _schedule('/schedules/replan', {
        ...plan.toRequestJson(),
        'completed_content_ids': plan.completedIds.toList(),
        'original_schedule': plan.schedule.toJson(),
      });

  Future<Schedule> _schedule(String path, Map<String, dynamic> payload) async {
    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 45));
      return Schedule.fromJson(_decode(response));
    } on TimeoutException {
      throw ApiException(
        '일정 생성이 예상보다 오래 걸리고 있어요. 잠시 후 다시 시도해 주세요.',
      );
    } on SocketException {
      throw ApiException('서버에 연결할 수 없습니다. API 주소와 네트워크를 확인해 주세요.');
    } on HttpException {
      throw ApiException('서버 응답을 처리할 수 없습니다.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('서버가 올바르지 않은 응답을 보냈습니다.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(decoded['detail'] as String? ?? '요청을 처리하지 못했습니다.');
    }
    return decoded;
  }
}

class LocalPlanDraft {
  LocalPlanDraft({
    required this.title,
    required this.kind,
    required this.contents,
    required this.preferences,
  });
  final String title;
  final PlanKind kind;
  final List<ContentItem> contents;
  final StudyPreferences preferences;

  Map<String, dynamic> toRequestJson() => {
        'book_title': title,
        'goal_type': kind.name,
        'contents': contents.map((item) => item.toJson()).toList(),
        'preferences': preferences.toJson(),
      };
}
