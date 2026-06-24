import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const defaultModelBaseUrl = 'https://api.deepseek.com/v1';
const defaultModelName = 'deepseek-chat';
const _thinkingContent = '正在思考...';

void main() {
  runApp(const AgentInterviewApp());
}

class AgentInterviewApp extends StatelessWidget {
  const AgentInterviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agent 面试机器人',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F2328),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.debugTrace,
  });

  final String role;
  final String content;
  final ModelDebugTrace? debugTrace;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (debugTrace != null) 'debugTrace': debugTrace!.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
      debugTrace: json['debugTrace'] == null
          ? null
          : ModelDebugTrace.fromJson(
              json['debugTrace'] as Map<String, dynamic>),
    );
  }
}

class ModelDebugTrace {
  const ModelDebugTrace({
    required this.requestJson,
    required this.responseJson,
    required this.retrievedKnowledgeJson,
    required this.processedAnswer,
  });

  final String requestJson;
  final String responseJson;
  final String retrievedKnowledgeJson;
  final String processedAnswer;

  Map<String, dynamic> toJson() => {
        'requestJson': requestJson,
        'responseJson': responseJson,
        'retrievedKnowledgeJson': retrievedKnowledgeJson,
        'processedAnswer': processedAnswer,
      };

  factory ModelDebugTrace.fromJson(Map<String, dynamic> json) {
    return ModelDebugTrace(
      requestJson: json['requestJson'] as String? ?? '',
      responseJson: json['responseJson'] as String? ?? '',
      retrievedKnowledgeJson: json['retrievedKnowledgeJson'] as String? ?? '',
      processedAnswer: json['processedAnswer'] as String? ?? '',
    );
  }
}

class ModelCallResult {
  const ModelCallResult({
    required this.answer,
    required this.debugTrace,
  });

  final String answer;
  final ModelDebugTrace debugTrace;
}

class ModelCallException implements Exception {
  const ModelCallException(this.message, this.debugTrace);

  final String message;
  final ModelDebugTrace debugTrace;

  @override
  String toString() => message;
}

class KnowledgeArticle {
  const KnowledgeArticle({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;

  factory KnowledgeArticle.fromJson(Map<String, dynamic> json) {
    return KnowledgeArticle(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
    );
  }
}

class RetrievedKnowledge {
  const RetrievedKnowledge({
    required this.id,
    required this.title,
    required this.source,
    required this.content,
    required this.score,
  });

  final String id;
  final String title;
  final String source;
  final String content;
  final double score;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'score': score,
        'content': content,
      };

  String get promptBlock =>
      '[$title source=$source score=${score.toStringAsFixed(3)}]\n$content';
}

class RetrievalSettings {
  const RetrievalSettings({
    required this.mode,
  });

  final String mode;

  bool get enabled => mode != 'disabled';

  EmbeddingProvider get provider {
    return switch (mode) {
      'disabled' => const DisabledEmbeddingProvider(),
      _ => const LocalHashEmbeddingProvider(),
    };
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
      };

  factory RetrievalSettings.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'] as String? ?? 'local_hash';
    return RetrievalSettings(
        mode: mode == 'disabled' ? 'disabled' : 'local_hash');
  }
}

abstract class EmbeddingProvider {
  const EmbeddingProvider();

  String get providerId;
  String get modelName;
  int get dimension;

  List<double> embed(String text);

  Map<String, dynamic> metadata() => {
        'embedding_provider': providerId,
        'embedding_model': modelName,
        'dimension': dimension,
      };
}

class LocalHashEmbeddingProvider extends EmbeddingProvider {
  const LocalHashEmbeddingProvider();

  @override
  String get providerId => 'local_hash';

  @override
  String get modelName => 'hashing-trick-v1';

  @override
  int get dimension => _embeddingDimensions;

  @override
  List<double> embed(String text) => _hashEmbedding(text);
}

class DisabledEmbeddingProvider extends EmbeddingProvider {
  const DisabledEmbeddingProvider();

  @override
  String get providerId => 'disabled';

  @override
  String get modelName => 'none';

  @override
  int get dimension => 0;

  @override
  List<double> embed(String text) => const [];
}

class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.category,
    required this.value,
    required this.source,
    required this.updatedAt,
    required this.confidence,
    this.enabled = true,
  });

  final String id;
  final String category;
  final String value;
  final String source;
  final DateTime updatedAt;
  final double confidence;
  final bool enabled;

  String get promptLine =>
      '[$category] $value (confidence=${confidence.toStringAsFixed(2)}, source=$source)';

  MemoryFact copyWith({
    String? id,
    String? category,
    String? value,
    String? source,
    DateTime? updatedAt,
    double? confidence,
    bool? enabled,
  }) {
    return MemoryFact(
      id: id ?? this.id,
      category: category ?? this.category,
      value: value ?? this.value,
      source: source ?? this.source,
      updatedAt: updatedAt ?? this.updatedAt,
      confidence: confidence ?? this.confidence,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'value': value,
        'source': source,
        'updatedAt': updatedAt.toIso8601String(),
        'confidence': confidence,
        'enabled': enabled,
      };

  factory MemoryFact.fromJson(Map<String, dynamic> json) {
    return MemoryFact(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      category: json['category'] as String? ?? 'profile',
      value: json['value'] as String? ?? '',
      source: json['source'] as String? ?? 'manual',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class ModelSettings {
  const ModelSettings({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String baseUrl;
  final String model;
  final String apiKey;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  ModelSettings copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return ModelSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

class LocalStore {
  static const _messagesKey = 'messages';
  static const _factsKey = 'facts';
  static const _memoryFactsKey = 'memory_facts';
  static const _baseUrlKey = 'model_base_url';
  static const _modelKey = 'model_name';
  static const _apiKeyKey = 'api_key';
  static const _retrievalSettingsKey = 'retrieval_settings';

  Future<List<ChatMessage>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_messagesKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMessages(List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final tail = messages.length > 40
        ? messages.sublist(messages.length - 40)
        : messages;
    await prefs.setString(
      _messagesKey,
      jsonEncode(tail.map((message) => message.toJson()).toList()),
    );
  }

  Future<List<String>> loadFacts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_factsKey) ?? [];
  }

  Future<void> saveFacts(List<String> facts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_factsKey, facts);
  }

  Future<List<MemoryFact>> loadMemoryFacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_memoryFactsKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => MemoryFact.fromJson(item as Map<String, dynamic>))
          .where((fact) => fact.value.trim().isNotEmpty)
          .toList();
    }

    final legacyFacts = prefs.getStringList(_factsKey) ?? [];
    return legacyFacts
        .where((fact) => fact.trim().isNotEmpty)
        .map(
          (fact) => MemoryFact(
            id: 'legacy-${fact.hashCode}',
            category: 'profile',
            value: fact,
            source: 'manual',
            updatedAt: DateTime.now(),
            confidence: 0.9,
          ),
        )
        .toList();
  }

  Future<void> saveMemoryFacts(List<MemoryFact> facts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _memoryFactsKey,
      jsonEncode(facts.map((fact) => fact.toJson()).toList()),
    );
  }

  Future<ModelSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return ModelSettings(
      baseUrl: prefs.getString(_baseUrlKey) ?? defaultModelBaseUrl,
      model: prefs.getString(_modelKey) ?? defaultModelName,
      apiKey: prefs.getString(_apiKeyKey) ?? '',
    );
  }

  Future<void> saveSettings(ModelSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, settings.baseUrl);
    await prefs.setString(_modelKey, settings.model);
    await prefs.setString(_apiKeyKey, settings.apiKey);
  }

  Future<RetrievalSettings> loadRetrievalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_retrievalSettingsKey);
    if (raw == null) return const RetrievalSettings(mode: 'local_hash');
    return RetrievalSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveRetrievalSettings(RetrievalSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_retrievalSettingsKey, jsonEncode(settings.toJson()));
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _store = LocalStore();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  LocalKnowledge _knowledge = LocalKnowledge.fallback();

  List<ChatMessage> _messages = [];
  List<MemoryFact> _memories = [];
  ModelSettings _settings = const ModelSettings(
    baseUrl: defaultModelBaseUrl,
    model: defaultModelName,
    apiKey: '',
  );
  RetrievalSettings _retrievalSettings =
      const RetrievalSettings(mode: 'local_hash');
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final messages = await _store.loadMessages();
    final memories = await _store.loadMemoryFacts();
    final settings = await _store.loadSettings();
    final retrievalSettings = await _store.loadRetrievalSettings();
    final knowledge = await LocalKnowledge.load();
    setState(() {
      _messages = messages.isEmpty
          ? [
              const ChatMessage(
                role: 'assistant',
                content:
                    '你好，我是 Agent 面试机器人。当前不用后端，记忆保存在本机。配置模型 API Key 后，我会直连大模型；不配置时，我用内置知识库给你练习。',
              ),
            ]
          : messages;
      _memories = memories;
      _settings = settings;
      _retrievalSettings = retrievalSettings;
      _knowledge = knowledge;
    });
    if (messages.isEmpty) {
      await _store.saveMessages(_messages);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _messages = [
        ..._messages,
        ChatMessage(role: 'user', content: question),
        const ChatMessage(role: 'assistant', content: _thinkingContent),
      ];
    });
    _controller.clear();
    _scrollToBottom();

    final retrievedKnowledge = _knowledge.retrieve(
      question,
      settings: _retrievalSettings,
    );
    late final ChatMessage assistantMessage;
    if (_settings.hasApiKey) {
      try {
        final result = await _callModel(retrievedKnowledge);
        assistantMessage = ChatMessage(
          role: 'assistant',
          content: result.answer,
          debugTrace: result.debugTrace,
        );
      } on ModelCallException catch (error) {
        final fallback =
            'Model call failed: ${error.message}\n\nFallback local demo:\n${_knowledge.demoAnswer(question, _enabledMemories, retrievedKnowledge)}';
        assistantMessage = ChatMessage(
          role: 'assistant',
          content: fallback,
          debugTrace: ModelDebugTrace(
            requestJson: error.debugTrace.requestJson,
            responseJson: error.debugTrace.responseJson,
            retrievedKnowledgeJson: error.debugTrace.retrievedKnowledgeJson,
            processedAnswer: fallback,
          ),
        );
      } catch (error) {
        assistantMessage = ChatMessage(
          role: 'assistant',
          content:
              'Model call failed: $error\n\nFallback local demo:\n${_knowledge.demoAnswer(question, _enabledMemories, retrievedKnowledge)}',
        );
      }
    } else {
      assistantMessage = ChatMessage(
          role: 'assistant',
          content: _knowledge.demoAnswer(
            question,
            _enabledMemories,
            retrievedKnowledge,
          ),
          debugTrace: ModelDebugTrace(
            requestJson: _prettyJson({
              'mode': 'local-demo',
              'question': question,
              'enabled_memories':
                  _enabledMemories.map((memory) => memory.toJson()).toList(),
            }),
            responseJson: _prettyJson({'mode': 'local-demo'}),
            retrievedKnowledgeJson: _retrievalTraceJson(retrievedKnowledge),
            processedAnswer: _knowledge.demoAnswer(
              question,
              _enabledMemories,
              retrievedKnowledge,
            ),
          ));
    }

    final nextMemories = _mergeMemories(_memories, _extractMemories(question));

    setState(() {
      _messages = [
        ..._messages.sublist(0, _messages.length - 1),
        assistantMessage,
      ];
      _memories = nextMemories;
      _sending = false;
    });
    await _store.saveMessages(_messages);
    await _store.saveMemoryFacts(_memories);
    _scrollToBottom();
  }

  Future<ModelCallResult> _callModel(
    List<RetrievedKnowledge> retrievedKnowledge,
  ) async {
    final endpoint =
        '${_settings.baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions';
    final conversation = _messages
        .where((message) => message.content != _thinkingContent)
        .toList();
    final requestBody = {
      'model': _settings.model,
      'messages': [
        {'role': 'system', 'content': _systemPrompt(retrievedKnowledge)},
        ...conversation.takeLast(8).map((message) => {
              'role': message.role,
              'content': message.content,
            }),
      ],
    };
    final requestDebugJson = _prettyJson({
      'endpoint': endpoint,
      'method': 'POST',
      'headers': {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ***redacted***',
      },
      'body': requestBody,
    });

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_settings.apiKey}',
      },
      body: jsonEncode(requestBody),
    );
    final responseText = utf8.decode(response.bodyBytes);
    final responseDebugJson = _prettyJsonOrText(responseText);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelCallException(
        'HTTP ${response.statusCode}',
        ModelDebugTrace(
          requestJson: requestDebugJson,
          responseJson: responseDebugJson,
          retrievedKnowledgeJson: _retrievalTraceJson(retrievedKnowledge),
          processedAnswer: '',
        ),
      );
    }

    final data = jsonDecode(responseText) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      const answer = 'The model returned no content.';
      return ModelCallResult(
        answer: answer,
        debugTrace: ModelDebugTrace(
          requestJson: requestDebugJson,
          responseJson: responseDebugJson,
          retrievedKnowledgeJson: _retrievalTraceJson(retrievedKnowledge),
          processedAnswer: answer,
        ),
      );
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final answer =
        message?['content'] as String? ?? 'The model returned no content.';
    return ModelCallResult(
      answer: answer,
      debugTrace: ModelDebugTrace(
        requestJson: requestDebugJson,
        responseJson: responseDebugJson,
        retrievedKnowledgeJson: _retrievalTraceJson(retrievedKnowledge),
        processedAnswer: answer,
      ),
    );
  }

  String _retrievalTraceJson(List<RetrievedKnowledge> retrievedKnowledge) {
    final provider = _retrievalSettings.provider;
    return _prettyJson({
      ...provider.metadata(),
      'retrieval_mode': _retrievalSettings.mode,
      'enabled': _retrievalSettings.enabled,
      'retrieved_chunks':
          retrievedKnowledge.map((item) => item.toJson()).toList(),
    });
  }

  String _systemPrompt(List<RetrievedKnowledge> retrievedKnowledge) {
    final factText = _enabledMemories.isEmpty
        ? 'none'
        : _enabledMemories.map((fact) => '- ${fact.promptLine}').join('\n');
    final retrievedText = retrievedKnowledge.isEmpty
        ? 'none'
        : retrievedKnowledge.map((item) => item.promptBlock).join('\n\n');
    return '''
You are an LLM Agent algorithm interview coach. Answer in Chinese with a clear interview-ready structure.

Local user memories:
$factText

Local knowledge retrieved for this question:
$retrievedText

Built-in knowledge base:
${_knowledge.promptContext}

Requirements:
1. Start with the core conflict.
2. Break down the system design.
3. End with engineering tradeoffs.
4. Use retrieved local knowledge when relevant, but do not invent external sources.
''';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearChat() async {
    setState(() {
      _messages = [
        const ChatMessage(
            role: 'assistant', content: '对话已清空。继续问我一个 Agent 面试题吧。'),
      ];
    });
    await _store.saveMessages(_messages);
  }

  Future<void> _openSettings() async {
    final result = await showModalBottomSheet<_SettingsResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SettingsSheet(
        settings: _settings,
        retrievalSettings: _retrievalSettings,
        memories: _memories,
      ),
    );
    if (result == null) return;
    setState(() {
      _settings = result.settings;
      _retrievalSettings = result.retrievalSettings;
      _memories = result.memories;
    });
    await _store.saveSettings(result.settings);
    await _store.saveRetrievalSettings(result.retrievalSettings);
    await _store.saveMemoryFacts(result.memories);
  }

  List<MemoryFact> get _enabledMemories =>
      _memories.where((memory) => memory.enabled).toList();

  List<MemoryFact> _extractMemories(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final lower = trimmed.toLowerCase();
    final extracted = <MemoryFact>[];

    void remember(String category, String value, double confidence) {
      extracted.add(
        MemoryFact(
          id: '${DateTime.now().microsecondsSinceEpoch}-${value.hashCode}',
          category: category,
          value: value,
          source: 'auto',
          updatedAt: DateTime.now(),
          confidence: confidence,
        ),
      );
    }

    if (lower.contains('rag') ||
        lower.contains('agent') ||
        lower.contains('transformer') ||
        lower.contains('long context')) {
      remember('learning_topic', 'Asked about: $trimmed', 0.62);
    }

    if (trimmed.contains('面试') ||
        lower.contains('interview') ||
        lower.contains('offer')) {
      remember('goal', 'Preparing for LLM/Agent interview topics', 0.78);
    }

    if (trimmed.contains('不懂') ||
        trimmed.contains('不会') ||
        lower.contains('confused')) {
      remember('weakness', 'Needs simpler explanation for: $trimmed', 0.7);
    }

    if (trimmed.contains('喜欢') ||
        trimmed.contains('希望') ||
        lower.contains('prefer')) {
      remember('preference', trimmed, 0.72);
    }

    return extracted;
  }

  List<MemoryFact> _mergeMemories(
    List<MemoryFact> current,
    List<MemoryFact> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final merged = [...current];
    for (final next in incoming) {
      final duplicateIndex = merged.indexWhere((memory) =>
          memory.category == next.category &&
          memory.value.trim().toLowerCase() == next.value.trim().toLowerCase());
      if (duplicateIndex >= 0) {
        merged[duplicateIndex] = merged[duplicateIndex].copyWith(
          updatedAt: DateTime.now(),
          confidence: next.confidence > merged[duplicateIndex].confidence
              ? next.confidence
              : merged[duplicateIndex].confidence,
        );
      } else {
        merged.add(next);
      }
    }
    merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged.length > 60 ? merged.take(60).toList() : merged;
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _settings.hasApiKey;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              connected: isConnected,
              model: _settings.model,
              onSettings: _openSettings,
              onClear: _clearChat,
            ),
            _QuickPrompts(onPick: _send),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                itemCount: _messages.length,
                itemBuilder: (context, index) =>
                    MessageBubble(message: _messages[index]),
              ),
            ),
            _Composer(
              controller: _controller,
              sending: _sending,
              onSend: () => _send(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.connected,
    required this.model,
    required this.onSettings,
    required this.onClear,
  });

  final bool connected;
  final String model;
  final VoidCallback onSettings;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2328),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'AI',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agent 面试机器人',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                Text(
                  connected ? '直连模型 · $model' : '本地 Demo · 本机记忆',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: connected
                          ? const Color(0xFF1F7A63)
                          : const Color(0xFF69707D)),
                ),
              ],
            ),
          ),
          IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话'),
          IconButton(
              onPressed: onSettings,
              icon: const Icon(Icons.tune),
              tooltip: '设置'),
        ],
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  const _QuickPrompts({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    const prompts = [
      ('记忆机制', '长期陪伴型 AI 的记忆机制怎么设计？'),
      ('RAG 工程', 'RAG 向量数据工程链路是什么？'),
      ('Long RAG', '长上下文模型会取代 RAG 吗？'),
      ('长上下文优化', 'Transformer 处理超长上下文有哪些瓶颈？'),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => ActionChip(
          label: Text(prompts[index].$1),
          onPressed: () => onPick(prompts[index].$2),
        ),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: prompts.length,
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF1F2328) : Colors.white,
          border: Border.all(
              color:
                  isUser ? const Color(0xFF1F2328) : const Color(0xFFDED8CB)),
          borderRadius: BorderRadius.circular(13),
          boxShadow: const [
            BoxShadow(
              color: Color(0x171F2328),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isUser ? Colors.white : const Color(0xFF1F2328),
                height: 1.58,
              ),
            ),
            if (!isUser && message.debugTrace != null) ...[
              const SizedBox(height: 10),
              ModelDebugPanel(trace: message.debugTrace!),
            ],
          ],
        ),
      ),
    );
  }
}

class ModelDebugPanel extends StatelessWidget {
  const ModelDebugPanel({required this.trace, super.key});

  final ModelDebugTrace trace;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text(
          '查看模型原始 JSON / 处理流程',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        children: [
          _DebugBlock(title: '发送给模型', value: trace.requestJson),
          _DebugBlock(
            title: '本地知识检索结果',
            value: trace.retrievedKnowledgeJson.isEmpty
                ? '[]'
                : trace.retrievedKnowledgeJson,
          ),
          _DebugBlock(title: '模型原始返回', value: trace.responseJson),
          _DebugBlock(title: '最终展示内容', value: trace.processedAnswer),
        ],
      ),
    );
  }
}

class _DebugBlock extends StatelessWidget {
  const _DebugBlock({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FA),
              border: Border.all(color: const Color(0xFFD0D7DE)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                value,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                  color: Color(0xFF24292F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFDED8CB))),
        color: Color(0xEEF4F1EA),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '问一个面试题，比如：RAG 为什么要混合检索？',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFDED8CB)),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: sending ? null : onSend,
            child: Text(sending ? '...' : '发送'),
          ),
        ],
      ),
    );
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    required this.settings,
    required this.retrievalSettings,
    required this.memories,
    super.key,
  });

  final ModelSettings settings;
  final RetrievalSettings retrievalSettings;
  final List<MemoryFact> memories;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  final _fact = TextEditingController();
  late String _retrievalMode;
  late List<MemoryFact> _memories;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _model = TextEditingController(text: widget.settings.model);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
    _retrievalMode = widget.retrievalSettings.mode;
    _memories = [...widget.memories];
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _fact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 0, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Model, Retrieval and Memory',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            const Text('Chat model',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                  labelText: 'DeepSeek / OpenAI-compatible Base URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Chat model'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Chat API Key'),
            ),
            const SizedBox(height: 18),
            const Text('Retrieval embedding',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _retrievalMode,
              decoration: const InputDecoration(labelText: 'Retrieval mode'),
              items: const [
                DropdownMenuItem(
                    value: 'local_hash', child: Text('Local Hash')),
                DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _retrievalMode = value);
              },
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final provider =
                    RetrievalSettings(mode: _retrievalMode).provider;
                return Text(
                  'Provider: ${provider.providerId} | Model: ${provider.modelName} | Dimension: ${provider.dimension}',
                  style:
                      const TextStyle(color: Color(0xFF69707D), height: 1.45),
                );
              },
            ),
            const SizedBox(height: 18),
            const Text('Local memory',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _fact,
              decoration:
                  const InputDecoration(labelText: 'Add profile memory'),
              onSubmitted: (_) => _addFact(),
            ),
            const SizedBox(height: 8),
            if (_memories.isEmpty)
              const Text(
                'No local memories yet.',
                style: TextStyle(color: Color(0xFF69707D)),
              )
            else
              Column(
                children: [
                  for (final memory in _memories)
                    MemoryFactTile(
                      memory: memory,
                      onToggle: (enabled) {
                        setState(() {
                          final index = _memories
                              .indexWhere((item) => item.id == memory.id);
                          if (index >= 0) {
                            _memories[index] =
                                _memories[index].copyWith(enabled: enabled);
                          }
                        });
                      },
                      onDelete: () {
                        setState(() => _memories
                            .removeWhere((item) => item.id == memory.id));
                      },
                    ),
                ],
              ),
            const SizedBox(height: 10),
            const Text(
              'Settings, chat history, memories, and the local knowledge base stay on this device. The chat API key is only used for direct model calls.',
              style: TextStyle(color: Color(0xFF69707D), height: 1.5),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                OutlinedButton(
                    onPressed: _addFact, child: const Text('Add memory')),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _SettingsResult(
                        settings: ModelSettings(
                          baseUrl: _baseUrl.text.trim().isEmpty
                              ? defaultModelBaseUrl
                              : _baseUrl.text.trim(),
                          model: _model.text.trim().isEmpty
                              ? defaultModelName
                              : _model.text.trim(),
                          apiKey: _apiKey.text.trim(),
                        ),
                        retrievalSettings:
                            RetrievalSettings(mode: _retrievalMode),
                        memories: _memories,
                      ),
                    );
                  },
                  child: const Text('Save settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addFact() {
    final value = _fact.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _memories.insert(
        0,
        MemoryFact(
          id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
          category: 'profile',
          value: value,
          source: 'manual',
          updatedAt: DateTime.now(),
          confidence: 0.95,
        ),
      );
      _fact.clear();
    });
  }
}

class MemoryFactTile extends StatelessWidget {
  const MemoryFactTile({
    required this.memory,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final MemoryFact memory;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: memory.enabled ? Colors.white : const Color(0xFFF6F8FA),
        border: Border.all(color: const Color(0xFFDED8CB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Switch(
            value: memory.enabled,
            onChanged: onToggle,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.value,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: memory.enabled
                        ? const Color(0xFF1F2328)
                        : const Color(0xFF69707D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${memory.category} · ${memory.source} · ${memory.confidence.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF69707D),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close),
            tooltip: 'Delete memory',
          ),
        ],
      ),
    );
  }
}

class _SettingsResult {
  const _SettingsResult({
    required this.settings,
    required this.retrievalSettings,
    required this.memories,
  });

  final ModelSettings settings;
  final RetrievalSettings retrievalSettings;
  final List<MemoryFact> memories;
}

class LocalKnowledge {
  const LocalKnowledge(this.articles);

  final List<KnowledgeArticle> articles;

  factory LocalKnowledge.fallback() {
    return const LocalKnowledge([
      KnowledgeArticle(
        id: 'memory',
        title: 'Long-term AI memory',
        content:
            'Layered memory includes short-term dialogue, structured user profile facts, and long-term episodic memories. Facts use structured storage while context uses semantic recall.',
      ),
      KnowledgeArticle(
        id: 'rag',
        title: 'RAG vector data engineering',
        content:
            'A RAG pipeline covers parsing, cleaning, metadata, semantic chunking, embedding, indexing, hybrid retrieval, reranking, generation, and evaluation.',
      ),
      KnowledgeArticle(
        id: 'long-rag',
        title: 'Long context and RAG',
        content:
            'Long context and RAG are complementary. RAG filters broad data cheaply, and long-context models deeply reason over selected evidence.',
      ),
      KnowledgeArticle(
        id: 'transformer',
        title: 'Transformer long-context bottlenecks',
        content:
            'Long-context bottlenecks include quadratic attention, KV cache memory pressure, IO bandwidth, and position extrapolation. Optimizations include FlashAttention, GQA, PagedAttention, and RoPE scaling.',
      ),
    ]);
  }

  static Future<LocalKnowledge> load() async {
    try {
      final raw = await rootBundle.loadString('assets/knowledge_base.json');
      final decoded = jsonDecode(raw) as List<dynamic>;
      return LocalKnowledge(
        decoded
            .map((item) =>
                KnowledgeArticle.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      return LocalKnowledge.fallback();
    }
  }

  List<RetrievedKnowledge> retrieve(
    String question, {
    required RetrievalSettings settings,
    int topK = 4,
  }) {
    if (!settings.enabled) return const [];
    final provider = settings.provider;
    final queryVector = provider.embed(question);
    final scored = _knowledgeChunks(articles, provider)
        .map((chunk) =>
            MapEntry(chunk, _cosineSimilarity(queryVector, chunk.vector)))
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = scored.isEmpty
        ? _fallbackChunks(articles, provider)
        : scored.take(topK);
    return selected
        .map(
          (entry) => RetrievedKnowledge(
            id: entry.key.id,
            title: entry.key.title,
            source: entry.key.source,
            content: entry.key.content,
            score: entry.value,
          ),
        )
        .toList();
  }

  String get promptContext {
    return articles
        .map((article) => '[${article.id}]\n${article.content}')
        .join('\n\n');
  }

  String demoAnswer(
    String question,
    List<MemoryFact> facts,
    List<RetrievedKnowledge> retrievedKnowledge,
  ) {
    final key = _pick(question);
    final base = _content(key);
    final factHint = facts.isEmpty
        ? ''
        : '\n\nLocal memories used: ${facts.map((fact) => fact.value).join('; ')}';
    final retrievedHint = retrievedKnowledge.isEmpty
        ? ''
        : '\n\nLocal knowledge used: ${retrievedKnowledge.map((item) => '${item.title}(${item.score.toStringAsFixed(3)})').join('; ')}';
    return '$base$factHint$retrievedHint\n\nInterview answer tip: start with the core conflict, then explain system design, and end with engineering tradeoffs.';
  }

  String _pick(String question) {
    final lower = question.toLowerCase();
    if (lower.contains('transformer') ||
        lower.contains('kv') ||
        lower.contains('attention') ||
        lower.contains('flashattention') ||
        lower.contains('gqa')) {
      return 'transformer';
    }
    if (lower.contains('long') ||
        lower.contains('context') ||
        lower.contains('token') ||
        lower.contains('latency')) {
      return 'long-rag';
    }
    if (lower.contains('rag') ||
        lower.contains('vector') ||
        lower.contains('embedding') ||
        lower.contains('retrieval') ||
        lower.contains('rerank')) {
      return 'rag';
    }
    if (lower.contains('memory') ||
        lower.contains('profile') ||
        lower.contains('preference')) {
      return 'memory';
    }
    return retrievedDefaultId;
  }

  String get retrievedDefaultId => articles.isEmpty ? 'rag' : articles.first.id;

  String _content(String key) {
    return articles
        .firstWhere(
          (article) => article.id == key,
          orElse: () => articles.isEmpty
              ? LocalKnowledge.fallback().articles.first
              : articles.first,
        )
        .content;
  }
}

const _embeddingDimensions = 96;
const _chunkSize = 240;
const _chunkOverlap = 48;

class _KnowledgeChunk {
  const _KnowledgeChunk({
    required this.id,
    required this.title,
    required this.source,
    required this.content,
    required this.vector,
  });

  final String id;
  final String title;
  final String source;
  final String content;
  final List<double> vector;
}

List<MapEntry<_KnowledgeChunk, double>> _fallbackChunks(
  List<KnowledgeArticle> articles,
  EmbeddingProvider provider,
) {
  final chunks = _knowledgeChunks(articles, provider);
  final fallback = chunks.firstWhere(
    (chunk) => chunk.source == 'rag',
    orElse: () => chunks.first,
  );
  return [MapEntry(fallback, 0.001)];
}

List<_KnowledgeChunk> _knowledgeChunks(
  List<KnowledgeArticle> articles,
  EmbeddingProvider provider,
) {
  final chunks = <_KnowledgeChunk>[];
  for (final article in articles) {
    final parts = _splitIntoChunks(article.content);
    for (var index = 0; index < parts.length; index += 1) {
      final content = parts[index];
      chunks.add(
        _KnowledgeChunk(
          id: '${article.id}:$index',
          title: article.title,
          source: article.id,
          content: content,
          vector: provider.embed('${article.title}\n$content'),
        ),
      );
    }
  }
  return chunks;
}

List<String> _splitIntoChunks(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  if (normalized.length <= _chunkSize) return [normalized];

  final chunks = <String>[];
  var start = 0;
  while (start < normalized.length) {
    final end = math.min(start + _chunkSize, normalized.length);
    chunks.add(normalized.substring(start, end).trim());
    if (end == normalized.length) break;
    start = math.max(0, end - _chunkOverlap);
  }
  return chunks;
}

List<double> _hashEmbedding(String text) {
  final vector = List<double>.filled(_embeddingDimensions, 0);
  for (final token in _tokens(text)) {
    final hash = token.hashCode;
    final index = hash.abs() % _embeddingDimensions;
    vector[index] += hash.isEven ? 1 : -1;
  }
  return vector;
}

Iterable<String> _tokens(String text) sync* {
  final lower = text.toLowerCase();
  final asciiTerms = RegExp(r'[a-z0-9_+#.-]+').allMatches(lower);
  for (final match in asciiTerms) {
    final value = match.group(0);
    if (value != null && value.length > 1) yield value;
  }

  final compact = lower.replaceAll(RegExp(r'\s+'), '');
  for (var i = 0; i < compact.length; i += 1) {
    final unit = compact.codeUnitAt(i);
    if (unit <= 127) continue;
    yield compact.substring(i, i + 1);
    if (i + 1 < compact.length && compact.codeUnitAt(i + 1) > 127) {
      yield compact.substring(i, i + 2);
    }
  }
}

double _cosineSimilarity(List<double> left, List<double> right) {
  var dot = 0.0;
  var leftNorm = 0.0;
  var rightNorm = 0.0;
  for (var i = 0; i < left.length; i += 1) {
    dot += left[i] * right[i];
    leftNorm += left[i] * left[i];
    rightNorm += right[i] * right[i];
  }
  if (leftNorm == 0 || rightNorm == 0) return 0;
  return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
}

String _prettyJson(Object value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}

String _prettyJsonOrText(String value) {
  try {
    return _prettyJson(jsonDecode(value));
  } catch (_) {
    return value;
  }
}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}
