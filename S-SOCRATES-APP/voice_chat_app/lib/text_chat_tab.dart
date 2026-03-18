import 'dart:async';

import 'package:flutter/material.dart';

import 'services/agent_api.dart';
import 'widgets/chat_bubble.dart';

class TextChatTab extends StatefulWidget {
  const TextChatTab({super.key});

  @override
  State<TextChatTab> createState() => _TextChatTabState();
}

class _TextChatTabState extends State<TextChatTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final AgentAPI _api = AgentAPI();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _sendCtrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'text': 'Xin chào! Tôi là S-Socrates AI. Hãy nhập câu hỏi của bạn vào bên dưới.',
      'user': false,
      'time': DateTime.now(),
    });
    _sendCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _sendCtrl.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _animatedSend() {
    if (_isLoading) return;
    _sendCtrl.forward(from: 0).then((_) {
      _sendCtrl.reverse();
    });
    _send();
  }

  Future<void> _send({String? forced}) async {
    final text = (forced ?? _controller.text).trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _messages.add({'text': text, 'user': true, 'time': DateTime.now()});
      _controller.clear();
    });
    _scrollDown();
    try {
      final reply = await _api.sendMessage(text);
      if (!mounted) return;
      setState(() =>
          _messages.add({'text': reply, 'user': false, 'time': DateTime.now()}));
      _scrollDown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyErr(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyErr(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('timeout') || m.contains('hết thời gian')) {
      return 'Backend phản hồi quá lâu. Vui lòng thử lại.';
    }
    if (m.contains('không kết nối') || m.contains('failed to fetch') || m.contains('clientexception')) {
      return 'Không kết nối được backend. Kiểm tra backend đang chạy + CORS.';
    }
    if (m.contains('500') || m.contains('ollama')) {
      return 'Backend lỗi. Kiểm tra Ollama có đang chạy không.';
    }
    return 'Có lỗi khi gửi tin nhắn. Vui lòng thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            decoration: BoxDecoration(
              color: const Color(0xFF091A15).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF275A48)),
            ),
            child: ListView.builder(
              controller: _scroll,
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return _typingIndicator();
                final m = _messages[i];
                return ChatBubble(
                  text: m['text'] as String,
                  isUser: m['user'] as bool,
                  timestamp: _fmt(m['time'] as DateTime),
                );
              },
            ),
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            ),
          ),
        _inputBar(),
      ],
    );
  }

  Widget _typingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F241D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2B6A53)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(const Color(0xFF16A34A)),
            _dot(const Color(0xFF22C55E)),
            _dot(const Color(0xFF86EFAC)),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _inputBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      padding: const EdgeInsets.fromLTRB(16, 5, 10, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A2018), Color(0xFF123729)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF2E7D5D),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _animatedSend(),
              style: const TextStyle(color: Color(0xFFE6FFF3)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Nhập câu hỏi của bạn...',
                hintStyle: TextStyle(color: Color(0xFFA7D9C2)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _sendCtrl,
            builder: (context, child) {
              final scale = 1.0 - 0.15 * _sendCtrl.value;
              final rotation = -0.5 * _sendCtrl.value;
              return Transform.scale(
                scale: scale,
                child: Transform.rotate(
                  angle: rotation,
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isLoading ? null : _animatedSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: _isLoading
                          ? [const Color(0xFF1A3D2E), const Color(0xFF1A3D2E)]
                          : [const Color(0xFF16A34A), const Color(0xFF22C55E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: _isLoading
                        ? []
                        : [
                            BoxShadow(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                    ),
                  child: Icon(
                    Icons.send_rounded,
                    color: _isLoading
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
