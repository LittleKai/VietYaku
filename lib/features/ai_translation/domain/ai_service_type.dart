/// Các nhà cung cấp dịch vụ AI được hỗ trợ trong VietYaku.
enum AiServiceType {
  geminiCli('Gemini CLI'),
  geminiApi('Gemini API'),
  chatGptApi('ChatGPT API'),
  claudeApi('Claude API'),
  grokApi('Grok API');

  final String label;
  const AiServiceType(this.label);

  /// Model mặc định cho từng dịch vụ
  String get defaultModel => switch (this) {
    AiServiceType.geminiCli => 'gemini-3-flash-preview',
    AiServiceType.geminiApi => 'gemini-3-flash-preview',
    AiServiceType.chatGptApi => 'gpt-4o-mini',
    AiServiceType.claudeApi => 'claude-3-5-haiku-20241022',
    AiServiceType.grokApi => 'grok-3-mini',
  };

  /// Danh sách các model chính xác của từng nhà cung cấp
  List<String> get availableModels => switch (this) {
    AiServiceType.geminiCli => const [
      'gemini-3-flash-preview',
      'gemini-3.1-pro-preview',
      'agy-gemini-3-flash',
      '假流式-agy-gemini-3-flash-low',
      'agy-gemini-3.5-flash-low',
      '假流式-agy-gemini-3.5-flash-low',
      'agy-gemini-3.6-flash',
      '假流式-agy-gemini-3.6-flash',
      'agy-gemini-3.6-flash-low',
      '假流式-agy-gemini-3.6-flash-low',
      'agy-gemini-3.1-pro-low',
      '假流式-agy-gemini-3.1-pro-low',
    ],
    AiServiceType.geminiApi => const [
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-2.5-pro',
      'gemini-3-flash-preview',
      'gemini-3-pro-preview',
      'gemini-3.1-flash-lite-preview',
      'gemini-3.1-pro-preview',
    ],
    AiServiceType.chatGptApi => const [
      'gpt-4o-mini',
      'gpt-4o',
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-5',
      'gpt-5-mini',
      'gpt-5-nano',
      'gpt-5.1',
      'gpt-5.2',
    ],
    AiServiceType.claudeApi => const [
      'claude-3-5-haiku-20241022',
      'claude-3-5-sonnet-20241022',
      'claude-3-7-sonnet-20250219',
      'claude-3-opus-20240229',
      'claude-haiku-4-5-20251001',
      'claude-sonnet-4-5-20250929',
      'claude-opus-4-5-20251101',
    ],
    AiServiceType.grokApi => const [
      'grok-3-mini',
      'grok-3',
      'grok-4-fast-non-reasoning',
      'grok-4-fast-reasoning',
      'grok-4-1-fast-non-reasoning',
      'grok-4-1-fast-reasoning',
    ],
  };

  /// URL trang tài liệu/hỗ trợ của dịch vụ
  String get helpUrl => switch (this) {
    AiServiceType.geminiCli => 'https://ai.google.dev/models/gemini',
    AiServiceType.geminiApi => 'https://ai.google.dev/models/gemini',
    AiServiceType.chatGptApi => 'https://platform.openai.com/docs/models',
    AiServiceType.claudeApi =>
      'https://platform.claude.com/docs/en/about-claude/models/overview',
    AiServiceType.grokApi => 'https://docs.x.ai/docs/models',
  };

  /// Proxy URL mặc định nếu là dịch vụ proxy (Gemini CLI)
  String get defaultProxyUrl => switch (this) {
    AiServiceType.geminiCli => 'https://gcli.ggchan.dev',
    _ => '',
  };

  /// Max tokens mặc định
  int get defaultMaxTokens => switch (this) {
    AiServiceType.geminiCli || AiServiceType.geminiApi => 8192,
    _ => 4096,
  };

  /// Request delay mặc định (giây)
  int get defaultRequestDelay => switch (this) {
    AiServiceType.geminiCli => 5,
    _ => 0,
  };

  /// Top K mặc định (chỉ Gemini hỗ trợ)
  int? get defaultTopK => switch (this) {
    AiServiceType.geminiCli || AiServiceType.geminiApi => 40,
    _ => null,
  };
}

/// Model reasoning của OpenAI (o-series và gpt-5*) không nhận `max_tokens`
/// (phải dùng `max_completion_tokens`) và chỉ chấp nhận `temperature`/`top_p`
/// mặc định — gửi kèm là lỗi 400.
bool isOpenAiReasoningModel(String model) {
  final m = model.toLowerCase();
  return m.startsWith('o1') ||
      m.startsWith('o3') ||
      m.startsWith('o4') ||
      m.startsWith('gpt-5');
}
