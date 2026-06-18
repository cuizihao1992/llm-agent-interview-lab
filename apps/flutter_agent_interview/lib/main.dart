import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
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
    final tail = messages.length > 40 ? messages.sublist(messages.length - 40) : messages;
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

  Future<ModelSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return ModelSettings(
      baseUrl: prefs.getString(_baseUrlKey) ?? 'https://api.openai.com/v1',
      model: prefs.getString(_modelKey) ?? 'gpt-4.1-mini',
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
  List<String> _facts = [];
  ModelSettings _settings = const ModelSettings(
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4.1-mini',
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
    final facts = await _store.loadFacts();
    final settings = await _store.loadSettings();
    setState(() {
      _messages = messages.isEmpty
          ? [
              const ChatMessage(
                role: 'assistant',
                content: '你好，我是 Agent 面试机器人。当前不用后端，记忆保存在本机。配置模型 API Key 后，我会直连大模型；不配置时，我用内置知识库给你练习。',
              ),
            ]
          : messages;
      _facts = facts;
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
        const ChatMessage(role: 'assistant', content: '正在思考...'),
      ];
    });
    _controller.clear();
    _scrollToBottom();

    final answer = _settings.hasApiKey
        ? await _callModel().catchError((Object error) {
            return '模型调用失败：$error\n\n已切换到本地 Demo：\n${_knowledge.demoAnswer(question, _facts)}';
          })
        : _knowledge.demoAnswer(question, _facts);

    setState(() {
      _messages = [
        ..._messages.sublist(0, _messages.length - 1),
        ChatMessage(role: 'assistant', content: answer),
      ];
      _sending = false;
    });
    await _store.saveMessages(_messages);
    _scrollToBottom();
  }

  Future<String> _callModel() async {
    final endpoint = '${_settings.baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions';
    final conversation = _messages.where((message) => message.content != '正在思考...').toList();
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_settings.apiKey}',
      },
      body: jsonEncode({
        'model': _settings.model,
        'messages': [
          {'role': 'system', 'content': _systemPrompt()},
          ...conversation.takeLast(8).map((message) => {
                'role': message.role,
                'content': message.content,
              }),
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return '模型没有返回内容。';
    final message = choices.first['message'] as Map<String, dynamic>?;
    return message?['content'] as String? ?? '模型没有返回内容。';
  }

  String _systemPrompt() {
    final factText = _facts.isEmpty ? '无' : _facts.map((fact) => '- $fact').join('\n');
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
        const ChatMessage(role: 'assistant', content: '对话已清空。继续问我一个 Agent 面试题吧。'),
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
        facts: _facts,
      ),
    );
    if (result == null) return;
    setState(() {
      _settings = result.settings;
      _facts = result.facts;
    });
    await _store.saveSettings(result.settings);
    await _store.saveFacts(result.facts);
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
                itemBuilder: (context, index) => MessageBubble(message: _messages[index]),
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
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
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
                  style: TextStyle(color: connected ? const Color(0xFF1F7A63) : const Color(0xFF69707D)),
                ),
              ],
            ),
          ),
          IconButton(onPressed: onClear, icon: const Icon(Icons.delete_outline), tooltip: '清空对话'),
          IconButton(onPressed: onSettings, icon: const Icon(Icons.tune), tooltip: '设置'),
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
    final prompts = const [
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF1F2328) : Colors.white,
          border: Border.all(color: isUser ? const Color(0xFF1F2328) : const Color(0xFFDED8CB)),
          borderRadius: BorderRadius.circular(13),
          boxShadow: const [
            BoxShadow(
              color: Color(0x171F2328),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser ? Colors.white : const Color(0xFF1F2328),
            height: 1.58,
          ),
        ),
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
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
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
    required this.facts,
    super.key,
  });

  final ModelSettings settings;
  final List<String> facts;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  final _fact = TextEditingController();
  late List<String> _facts;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _model = TextEditingController(text: widget.settings.model);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
    _facts = [...widget.facts];
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
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('模型与本地记忆', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(labelText: 'OpenAI-compatible Base URL'),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final fact in _facts)
                  InputChip(
                    label: Text(fact),
                    onDeleted: () => setState(() => _facts.remove(fact)),
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
                          baseUrl: _baseUrl.text.trim().isEmpty ? 'https://api.openai.com/v1' : _baseUrl.text.trim(),
                          model: _model.text.trim().isEmpty ? 'gpt-4.1-mini' : _model.text.trim(),
                          apiKey: _apiKey.text.trim(),
                        ),
                        facts: _facts,
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
      _facts.add(value);
      _fact.clear();
    });
  }
}

class _SettingsResult {
  const _SettingsResult({
    required this.settings,
    required this.facts,
  });

  final ModelSettings settings;
  final List<String> facts;
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

  String demoAnswer(String question, List<String> facts) {
    final key = _pick(question);
    final factHint = facts.isEmpty ? '' : '\n\n结合你的本地画像：${facts.join('；')}';
    return '${_content(key)}$factHint\n\n面试表达建议：先讲核心矛盾，再拆系统结构，最后补工程取舍。';
  }

  String _pick(String question) {
    final lower = question.toLowerCase();
    if (lower.contains('transformer') || lower.contains('kv') || question.contains('长上下文优化')) {
      return 'transformer';
    }
    if (lower.contains('long') || question.contains('取代') || question.contains('长上下文')) {
      return 'long-rag';
    }
    if (lower.contains('rag') || question.contains('向量') || question.contains('检索')) {
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

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}
