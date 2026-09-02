import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ai_key_rotator.dart';
import '../domain/ai_service_config.dart';
import '../domain/ai_service_type.dart';

class AiApiResponse {
  final String? text;
  final String? error;

  const AiApiResponse({this.text, this.error});

  bool get isSuccess => text != null && text!.trim().isNotEmpty;
}

/// Kết quả một lần gọi bằng MỘT key. [cooldown] khác null nghĩa là lỗi thuộc
/// về chính key đó (sai key / hết hạn ngạch) → tạm loại key và xoay sang key
/// kế tiếp, thay vì trả lỗi ngay cho người dùng.
class _Attempt {
  final AiApiResponse response;
  final Duration? cooldown;

  const _Attempt(this.response, {this.cooldown});
}

class AiApiClient {
  /// Key sai hoặc hết hạn: nghỉ lâu, gần như chắc chắn không tự hồi.
  static const _invalidKeyCooldown = Duration(minutes: 30);

  /// Đụng rate limit: nghỉ ngắn rồi cho dùng lại.
  static const _rateLimitCooldown = Duration(minutes: 1);

  /// Tối đa số key thử trong một lần tra, để một cụm từ không đốt cả bộ key.
  static const _maxAttempts = 3;

  final http.Client _client;
  final Map<AiServiceType, AiKeyRotator> _rotators = {};
  final Map<String, DateTime> _cooldownUntil = {};
  final Map<AiServiceType, DateTime> _lastRequestTimes = {};

  AiApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// Các key đang bị tạm loại (đã bỏ những key hết hạn cooldown).
  Set<String> get failedKeys {
    final now = DateTime.now();
    _cooldownUntil.removeWhere((_, until) => !until.isAfter(now));
    return Set.unmodifiable(_cooldownUntil.keys);
  }

  /// Cho phép dùng lại toàn bộ key ngay — gọi khi người dùng vừa sửa cấu hình.
  void resetFailedKeys() => _cooldownUntil.clear();

  Future<void> _applyRequestDelay(
    AiServiceType serviceType,
    int delaySeconds,
  ) async {
    if (delaySeconds <= 0) return;
    final lastTime = _lastRequestTimes[serviceType];
    if (lastTime != null) {
      final elapsed = DateTime.now().difference(lastTime).inMilliseconds;
      final waitMs = (delaySeconds * 1000) - elapsed;
      if (waitMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
    }
    _lastRequestTimes[serviceType] = DateTime.now();
  }

  /// Gửi prompt đến dịch vụ AI đã cấu hình, xoay vòng key theo trọng số.
  Future<AiApiResponse> callAi({
    required String prompt,
    required AiServiceType serviceType,
    required AiServiceConfig config,
  }) async {
    if (config.keys.isEmpty) {
      return AiApiResponse(
        error:
            'Chưa có API key nào cho ${serviceType.label}. Hãy vào Cài đặt → Dịch AI để thêm key.',
      );
    }

    final rotator = _rotators.putIfAbsent(serviceType, AiKeyRotator.new);
    final attempts = config.keys.length < _maxAttempts
        ? config.keys.length
        : _maxAttempts;

    AiApiResponse? lastError;
    for (var i = 0; i < attempts; i++) {
      final key = rotator.next(config.keys, skip: failedKeys);
      if (key == null) break;

      await _applyRequestDelay(serviceType, config.requestDelay);
      final attempt = await _dispatch(prompt, key.value, serviceType, config);

      if (attempt.cooldown == null) return attempt.response;

      _cooldownUntil[key.value] = DateTime.now().add(attempt.cooldown!);
      lastError = attempt.response;
    }

    return lastError ??
        AiApiResponse(
          error:
              'Toàn bộ API key của ${serviceType.label} đang tạm bị loại (sai key hoặc quá hạn ngạch). Kiểm tra lại trong Cài đặt → Dịch AI.',
        );
  }

  Future<_Attempt> _dispatch(
    String prompt,
    String apiKey,
    AiServiceType serviceType,
    AiServiceConfig config,
  ) => switch (serviceType) {
    AiServiceType.geminiCli => _callGeminiCli(prompt, apiKey, config),
    AiServiceType.geminiApi => _callGeminiApi(prompt, apiKey, config),
    AiServiceType.chatGptApi => _callOpenAi(prompt, apiKey, config),
    AiServiceType.claudeApi => _callClaude(prompt, apiKey, config),
    AiServiceType.grokApi => _callGrok(prompt, apiKey, config),
  };

  /// Lỗi thuộc về key: 401/403 sai key, 429 hết hạn ngạch tức thời.
  _Attempt? _keyLevelFailure(
    int statusCode,
    String apiKey,
    String serviceLabel,
  ) {
    if (statusCode == 401 || statusCode == 403) {
      return _Attempt(
        AiApiResponse(
          error:
              '[Mã $statusCode] API Key $serviceLabel không hợp lệ hoặc đã hết hạn: ${AiSettings.maskKey(apiKey)}',
        ),
        cooldown: _invalidKeyCooldown,
      );
    }
    if (statusCode == 429) {
      return _Attempt(
        AiApiResponse(
          error:
              '[Mã 429] Key ${AiSettings.maskKey(apiKey)} bị giới hạn tốc độ / hết hạn ngạch. Đã tạm chuyển sang key khác.',
        ),
        cooldown: _rateLimitCooldown,
      );
    }
    return null;
  }

  Future<_Attempt> _callGeminiCli(
    String prompt,
    String apiKey,
    AiServiceConfig config,
  ) async {
    final proxyUrl = config.proxyUrl.trim().isNotEmpty
        ? config.proxyUrl.trim().replaceFirst(RegExp(r'/+$'), '')
        : 'https://gcli.ggchan.dev';
    final url = Uri.parse('$proxyUrl/v1/chat/completions');

    final payload = {
      'model': config.selectedModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'max_tokens': config.maxTokens,
      'temperature': config.temperature,
      'top_p': config.topP,
    };

    try {
      final response = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.timeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map &&
            data['choices'] is List &&
            (data['choices'] as List).isNotEmpty) {
          final choice = data['choices'][0];
          final text = choice['message']?['content']?.toString();
          if (text != null && text.trim().isNotEmpty) {
            return _Attempt(AiApiResponse(text: text.trim()));
          }
          final finishReason = choice['finish_reason'];
          return _Attempt(
            AiApiResponse(
              error: 'AI không trả về nội dung (finish_reason: $finishReason).',
            ),
          );
        }
        return const _Attempt(
          AiApiResponse(error: 'Phản hồi từ Gemini CLI không đúng định dạng.'),
        );
      }

      final keyFailure = _keyLevelFailure(
        response.statusCode,
        apiKey,
        'Gemini CLI',
      );
      if (keyFailure != null) return keyFailure;

      return _Attempt(
        AiApiResponse(
          error:
              '[Mã ${response.statusCode}] ${response.body.isNotEmpty ? response.body : "Lỗi kết nối máy chủ proxy"}',
        ),
      );
    } on TimeoutException {
      return _Attempt(
        AiApiResponse(
          error:
              'Yêu cầu tới Gemini CLI quá thời gian chờ (${config.timeout}s).',
        ),
      );
    } catch (e) {
      return _Attempt(AiApiResponse(error: 'Lỗi gọi Gemini CLI: $e'));
    }
  }

  Future<_Attempt> _callGeminiApi(
    String prompt,
    String apiKey,
    AiServiceConfig config,
  ) async {
    final model = config.selectedModel;
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': config.temperature,
        'maxOutputTokens': config.maxTokens,
        'topP': config.topP,
        if (config.topK != null) 'topK': config.topK,
      },
    };

    try {
      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.timeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map &&
            data['candidates'] is List &&
            (data['candidates'] as List).isNotEmpty) {
          final candidate = data['candidates'][0];
          final parts = candidate['content']?['parts'];
          if (parts is List && parts.isNotEmpty) {
            final text = parts[0]['text']?.toString();
            if (text != null && text.trim().isNotEmpty) {
              return _Attempt(AiApiResponse(text: text.trim()));
            }
          }
        }
        return const _Attempt(
          AiApiResponse(error: 'Không nhận được nội dung từ Gemini API.'),
        );
      }

      final keyFailure = _keyLevelFailure(
        response.statusCode,
        apiKey,
        'Google Gemini',
      );
      if (keyFailure != null) return keyFailure;

      return _Attempt(
        AiApiResponse(error: '[Mã ${response.statusCode}] ${response.body}'),
      );
    } on TimeoutException {
      return _Attempt(
        AiApiResponse(
          error: 'Yêu cầu tới Gemini API quá thời gian (${config.timeout}s).',
        ),
      );
    } catch (e) {
      return _Attempt(AiApiResponse(error: 'Lỗi gọi Gemini API: $e'));
    }
  }

  Future<_Attempt> _callOpenAi(
    String prompt,
    String apiKey,
    AiServiceConfig config,
  ) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final isReasoning = isOpenAiReasoningModel(config.selectedModel);

    // o-series và gpt-5* đổi tên tham số token và từ chối temperature/top_p
    // khác mặc định — gửi kèm là lỗi 400.
    final payload = {
      'model': config.selectedModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      if (isReasoning)
        'max_completion_tokens': config.maxTokens
      else ...{
        'max_tokens': config.maxTokens,
        'temperature': config.temperature,
        'top_p': config.topP,
      },
    };

    try {
      final response = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.timeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map &&
            data['choices'] is List &&
            (data['choices'] as List).isNotEmpty) {
          final choice = data['choices'][0];
          final text = choice['message']?['content']?.toString();
          if (text != null && text.trim().isNotEmpty) {
            return _Attempt(AiApiResponse(text: text.trim()));
          }
        }
        return const _Attempt(
          AiApiResponse(error: 'Không nhận được nội dung từ ChatGPT API.'),
        );
      }

      final keyFailure = _keyLevelFailure(
        response.statusCode,
        apiKey,
        'OpenAI',
      );
      if (keyFailure != null) return keyFailure;

      return _Attempt(
        AiApiResponse(error: '[Mã ${response.statusCode}] ${response.body}'),
      );
    } on TimeoutException {
      return _Attempt(
        AiApiResponse(
          error: 'Yêu cầu tới ChatGPT API quá thời gian (${config.timeout}s).',
        ),
      );
    } catch (e) {
      return _Attempt(AiApiResponse(error: 'Lỗi gọi ChatGPT API: $e'));
    }
  }

  Future<_Attempt> _callClaude(
    String prompt,
    String apiKey,
    AiServiceConfig config,
  ) async {
    final url = Uri.parse('https://api.anthropic.com/v1/messages');

    // Claude 4.x trả 400 nếu gửi cả temperature lẫn top_p → chỉ gửi temperature.
    final payload = {
      'model': config.selectedModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'max_tokens': config.maxTokens,
      'temperature': config.temperature,
    };

    try {
      final response = await _client
          .post(
            url,
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.timeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map &&
            data['content'] is List &&
            (data['content'] as List).isNotEmpty) {
          final contentItem = data['content'][0];
          final text = contentItem['text']?.toString();
          if (text != null && text.trim().isNotEmpty) {
            return _Attempt(AiApiResponse(text: text.trim()));
          }
        }
        return const _Attempt(
          AiApiResponse(error: 'Không nhận được nội dung từ Claude API.'),
        );
      }

      final keyFailure = _keyLevelFailure(
        response.statusCode,
        apiKey,
        'Claude',
      );
      if (keyFailure != null) return keyFailure;

      return _Attempt(
        AiApiResponse(error: '[Mã ${response.statusCode}] ${response.body}'),
      );
    } on TimeoutException {
      return _Attempt(
        AiApiResponse(
          error: 'Yêu cầu tới Claude API quá thời gian (${config.timeout}s).',
        ),
      );
    } catch (e) {
      return _Attempt(AiApiResponse(error: 'Lỗi gọi Claude API: $e'));
    }
  }

  Future<_Attempt> _callGrok(
    String prompt,
    String apiKey,
    AiServiceConfig config,
  ) async {
    final url = Uri.parse('https://api.x.ai/v1/chat/completions');

    final payload = {
      'model': config.selectedModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'max_tokens': config.maxTokens,
      'temperature': config.temperature,
      'top_p': config.topP,
    };

    try {
      final response = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.timeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map &&
            data['choices'] is List &&
            (data['choices'] as List).isNotEmpty) {
          final choice = data['choices'][0];
          final text = choice['message']?['content']?.toString();
          if (text != null && text.trim().isNotEmpty) {
            return _Attempt(AiApiResponse(text: text.trim()));
          }
        }
        return const _Attempt(
          AiApiResponse(error: 'Không nhận được nội dung từ Grok API.'),
        );
      }

      final keyFailure = _keyLevelFailure(
        response.statusCode,
        apiKey,
        'Grok',
      );
      if (keyFailure != null) return keyFailure;

      return _Attempt(
        AiApiResponse(error: '[Mã ${response.statusCode}] ${response.body}'),
      );
    } on TimeoutException {
      return _Attempt(
        AiApiResponse(
          error: 'Yêu cầu tới Grok API quá thời gian (${config.timeout}s).',
        ),
      );
    } catch (e) {
      return _Attempt(AiApiResponse(error: 'Lỗi gọi Grok API: $e'));
    }
  }
}
