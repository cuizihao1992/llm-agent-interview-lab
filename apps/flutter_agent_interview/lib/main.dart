import 'dart:convert';

import 'package:flutter/material.dart';
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
    required this.processedAnswer,
  });

  final String requestJson;
  final String responseJson;
  final String processedAnswer;

  Map<String, dynamic> toJson() => {
        'requestJson': requestJson,
        'responseJson': responseJson,
        'processedAnswer': processedAnswer,
      };

  factory ModelDebugTrace.fromJson(Map<String, dynamic> json) {
    return ModelDebugTrace(
      requestJson: json['requestJson'] as String? ?? '',
      responseJson: json['responseJson'] as String? ?? '',
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
  final _knowledge = const LocalKnowledge();

  List<ChatMessage> _messages = [];
  List<MemoryFact> _memories = [];
  ModelSettings _settings = const ModelSettings(
    baseUrl: defaultModelBaseUrl,
    model: defaultModelName,
    apiKey: '',
  );
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

    late final ChatMessage assistantMessage;
    if (_settings.hasApiKey) {
      try {
        final result = await _callModel();
        assistantMessage = ChatMessage(
          role: 'assistant',
          content: result.answer,
          debugTrace: result.debugTrace,
        );
      } on ModelCallException catch (error) {
        final fallback =
            'Model call failed: ${error.message}\n\nFallback local demo:\n${_knowledge.demoAnswer(question, _enabledMemories)}';
        assistantMessage = ChatMessage(
          role: 'assistant',
          content: fallback,
          debugTrace: ModelDebugTrace(
            requestJson: error.debugTrace.requestJson,
            responseJson: error.debugTrace.responseJson,
            processedAnswer: fallback,
          ),
        );
      } catch (error) {
        assistantMessage = ChatMessage(
          role: 'assistant',
          content:
              'Model call failed: $error\n\nFallback local demo:\n${_knowledge.demoAnswer(question, _enabledMemories)}',
        );
      }
    } else {
      assistantMessage = ChatMessage(
          role: 'assistant',
          content: _knowledge.demoAnswer(question, _enabledMemories));
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

  Future<ModelCallResult> _callModel() async {
    final endpoint =
        '${_settings.baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions';
    final conversation = _messages
        .where((message) => message.content != _thinkingContent)
        .toList();
    final requestBody = {
      'model': _settings.model,
      'messages': [
        {'role': 'system', 'content': _systemPrompt()},
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
        processedAnswer: answer,
      ),
    );
  }

  String _systemPrompt() {
    final factText = _enabledMemories.isEmpty
        ? 'none'
        : _enabledMemories.map((fact) => '- ${fact.promptLine}').join('\n');
    return '''
你是一个大模型 Agent 算法面试陪练。请用中文回答，结构清晰，优先给出面试可表达的答案。

本地用户画像：
$factText

内置知识库：
${_knowledge.promptContext}

要求：
1. 先讲核心矛盾。
2. 再拆系统结构。
3. 最后补工程取舍。
4. 不要声称你做了 RAG 检索；当前版本只使用内置知识和本地记忆。
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
        memories: _memories,
      ),
    );
    if (result == null) return;
    setState(() {
      _settings = result.settings;
      _memories = result.memories;
    });
    await _store.saveSettings(result.settings);
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
    required this.memories,
    super.key,
  });

  final ModelSettings settings;
  final List<MemoryFact> memories;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  final _fact = TextEditingController();
  late List<MemoryFact> _memories;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _model = TextEditingController(text: widget.settings.model);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
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
            const Text('模型与本地记忆',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                  labelText: 'DeepSeek / OpenAI-compatible Base URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _fact,
              decoration: const InputDecoration(labelText: '添加用户画像事实'),
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
              '当前版本不用后端，不做 RAG 请求。设置、对话和记忆都保存在当前设备。配置 API Key 后，App 会直连大模型接口。',
              style: TextStyle(color: Color(0xFF69707D), height: 1.5),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                OutlinedButton(onPressed: _addFact, child: const Text('保存画像')),
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
                        memories: _memories,
                      ),
                    );
                  },
                  child: const Text('保存设置'),
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
    required this.memories,
  });

  final ModelSettings settings;
  final List<MemoryFact> memories;
}

class LocalKnowledge {
  const LocalKnowledge();

  String get promptContext => '''
[memory]
$memory

[rag]
$rag

[long-rag]
$longRag

[transformer]
$transformer
''';

  String demoAnswer(String question, List<MemoryFact> facts) {
    final key = _pick(question);
    final factHint = facts.isEmpty
        ? ''
        : '\n\nLocal memories used: ${facts.map((fact) => fact.value).join('; ')}';
    return '${_content(key)}$factHint\n\n面试表达建议：先讲核心矛盾，再拆系统结构，最后补工程取舍。';
  }

  String _pick(String question) {
    final lower = question.toLowerCase();
    if (lower.contains('transformer') ||
        lower.contains('kv') ||
        question.contains('长上下文优化')) {
      return 'transformer';
    }
    if (lower.contains('long') ||
        question.contains('取代') ||
        question.contains('长上下文')) {
      return 'long-rag';
    }
    if (lower.contains('rag') ||
        question.contains('向量') ||
        question.contains('检索')) {
      return 'rag';
    }
    if (question.contains('记忆') || question.contains('画像')) {
      return 'memory';
    }
    return 'rag';
  }

  String _content(String key) {
    return switch (key) {
      'memory' => memory,
      'long-rag' => longRag,
      'transformer' => transformer,
      _ => rag,
    };
  }

  static const memory =
      '长期陪伴型 AI 不应把所有历史塞进 prompt。更稳的方案是分层记忆：近期多轮对话作为短期记忆；用户身份、偏好、目标等事实抽取成结构化画像；闲聊、项目背景、感悟等内容作为长期情景记忆。生成时按需召回，更新时用异步任务做事实抽取、冲突合并和遗忘。';

  static const rag =
      'RAG 要按数据工程链路来设计：先解析 PDF、网页、Markdown 等文档并清洗噪音，再提取元数据；切片时按标题、段落和语义边界切分，保留重叠；向量化后写入向量库；检索阶段用向量 + 关键词混合检索，再用 reranker 重排；最后用召回率、引用准确性、幻觉率、延迟和成本做闭环评估。';

  static const longRag =
      '长上下文不会简单取代 RAG。RAG 的价值是从海量资料里低成本、低延迟、可权限控制地筛选相关内容；长上下文模型适合对筛选后的高质量材料精读和跨文档推理。未来更现实的是 Long RAG：先召回，再精读。';

  static const transformer =
      'Transformer 处理超长上下文的核心瓶颈是自注意力 O(n^2) 计算复杂度、KV Cache 显存与带宽压力、显存 IO 瓶颈以及位置编码外推能力。常见优化包括 FlashAttention、GQA、PagedAttention、RoPE Scaling、ALiBi 等。';
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
