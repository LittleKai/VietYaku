import 'ai_api_key.dart';
import 'ai_service_type.dart';

class AiServiceConfig {
  final List<AiApiKey> keys;
  final String selectedModel;
  final double temperature;
  final int maxTokens;
  final double topP;
  final int? topK;
  final int requestDelay;
  final int timeout;
  final String proxyUrl;

  const AiServiceConfig({
    this.keys = const [],
    required this.selectedModel,
    this.temperature = 0.7,
    this.maxTokens = 8192,
    this.topP = 0.95,
    this.topK,
    this.requestDelay = 0,
    this.timeout = 240,
    this.proxyUrl = '',
  });

  factory AiServiceConfig.defaultsFor(AiServiceType type) => AiServiceConfig(
    keys: const [],
    selectedModel: type.defaultModel,
    temperature: 0.7,
    maxTokens: type.defaultMaxTokens,
    topP: 0.95,
    topK: type.defaultTopK,
    requestDelay: type.defaultRequestDelay,
    timeout: 240,
    proxyUrl: type.defaultProxyUrl,
  );

  AiServiceConfig copyWith({
    List<AiApiKey>? keys,
    String? selectedModel,
    double? temperature,
    int? maxTokens,
    double? topP,
    int? topK,
    int? requestDelay,
    int? timeout,
    String? proxyUrl,
  }) => AiServiceConfig(
    keys: keys ?? this.keys,
    selectedModel: selectedModel ?? this.selectedModel,
    temperature: temperature ?? this.temperature,
    maxTokens: maxTokens ?? this.maxTokens,
    topP: topP ?? this.topP,
    topK: topK ?? this.topK,
    requestDelay: requestDelay ?? this.requestDelay,
    timeout: timeout ?? this.timeout,
    proxyUrl: proxyUrl ?? this.proxyUrl,
  );

  Map<String, dynamic> toJson() => {
    'keys': [for (final k in keys) k.toJson()],
    'selected_model': selectedModel,
    'temperature': temperature,
    'max_tokens': maxTokens,
    'top_p': topP,
    if (topK != null) 'top_k': topK,
    'request_delay': requestDelay,
    'timeout': timeout,
    if (proxyUrl.isNotEmpty) 'proxy_url': proxyUrl,
  };

  factory AiServiceConfig.fromJson(
    Map<String, dynamic> json,
    AiServiceType type,
  ) {
    final keysList = AiApiKey.parseList(json['keys']);
    final model = (json['selected_model'] as String?)?.trim();
    final validModel = (model != null && model.isNotEmpty)
        ? model
        : type.defaultModel;

    return AiServiceConfig(
      keys: keysList,
      selectedModel: validModel,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: (json['max_tokens'] as num?)?.toInt() ?? type.defaultMaxTokens,
      topP: (json['top_p'] as num?)?.toDouble() ?? 0.95,
      topK: (json['top_k'] as num?)?.toInt() ?? type.defaultTopK,
      requestDelay:
          (json['request_delay'] as num?)?.toInt() ?? type.defaultRequestDelay,
      timeout: (json['timeout'] as num?)?.toInt() ?? 240,
      proxyUrl: (json['proxy_url'] as String?) ?? type.defaultProxyUrl,
    );
  }
}

class AiSettings {
  final AiServiceType activeService;
  final Map<AiServiceType, AiServiceConfig> serviceConfigs;

  const AiSettings({
    this.activeService = AiServiceType.geminiCli,
    required this.serviceConfigs,
  });

  AiServiceConfig get activeConfig =>
      serviceConfigs[activeService] ??
      AiServiceConfig.defaultsFor(activeService);

  bool get hasConfiguredKey => activeConfig.keys.isNotEmpty;

  /// Ẩn key để hiển thị an toàn trên UI (VD: `AIzaSyAxfa...QkGw`)
  static String maskKey(String key) {
    final trimmed = key.trim();
    if (trimmed.length <= 10) {
      return '*' * trimmed.length;
    }
    return '${trimmed.substring(0, 6)}...${trimmed.substring(trimmed.length - 4)}';
  }

  AiSettings copyWith({
    AiServiceType? activeService,
    Map<AiServiceType, AiServiceConfig>? serviceConfigs,
  }) => AiSettings(
    activeService: activeService ?? this.activeService,
    serviceConfigs: serviceConfigs ?? this.serviceConfigs,
  );

  static AiSettings defaults() => AiSettings(
    activeService: AiServiceType.geminiCli,
    serviceConfigs: {
      for (final type in AiServiceType.values)
        type: AiServiceConfig.defaultsFor(type),
    },
  );

  Map<String, dynamic> toJson() => {
    'active_service': activeService.name,
    'services': {
      for (final entry in serviceConfigs.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  factory AiSettings.fromJson(Map<String, dynamic> json) {
    final activeName = json['active_service'] as String?;
    final active =
        AiServiceType.values.asNameMap()[activeName] ??
        AiServiceType.geminiCli;

    final servicesMap = <AiServiceType, AiServiceConfig>{};
    final rawServices = json['services'];

    for (final type in AiServiceType.values) {
      if (rawServices is Map && rawServices[type.name] is Map) {
        servicesMap[type] = AiServiceConfig.fromJson(
          Map<String, dynamic>.from(rawServices[type.name] as Map),
          type,
        );
      } else if (rawServices is Map && rawServices[type.label] is Map) {
        // Hỗ trợ cả key bằng label ("Gemini CLI")
        servicesMap[type] = AiServiceConfig.fromJson(
          Map<String, dynamic>.from(rawServices[type.label] as Map),
          type,
        );
      } else {
        servicesMap[type] = AiServiceConfig.defaultsFor(type);
      }
    }

    return AiSettings(activeService: active, serviceConfigs: servicesMap);
  }
}
