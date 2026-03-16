import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _voiceSupported = false;
  String _liveTranscript = '';
  String? _errorMessage;

  late final AnimationController _pulseCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _sendCtrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'text': 'Xin chào! Tôi là S-Socrates AI. Hãy nhập câu hỏi hoặc bấm mic để nói.',
      'user': false,
      'time': DateTime.now(),
    });
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _sendCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (!mounted) return;
        debugPrint('STT(chat): status="$s"');
        final n = s.toLowerCase().replaceAll('_', '');
        if (n == 'done' || n == 'notlistening') {
          _finishListening();
        }
      },
      onError: (e) {
        debugPrint('STT(chat): error=$e');
        if (!mounted) return;
        _finishListening();
      },
    );
    debugPrint('STT(chat): initialize ok=$ok');
    if (mounted) setState(() => _voiceSupported = ok);
  }

  void _finishListening() {
    if (!_isListening) return;
    final text = _liveTranscript.trim();
    final elapsed = _micStartTime != null
        ? DateTime.now().difference(_micStartTime!).inMilliseconds
        : 0;

    // Auto-retry on quick fail (browser flake)
    if (text.isEmpty && elapsed < 2000 && _micRetryCount < 3) {
      _micRetryCount++;
      debugPrint('STT(chat): Quick fail (${elapsed}ms), auto-retry #$_micRetryCount');
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_isLoading) {
          _startMic(isRetry: true);
        }
      });
      return;
    }

    setState(() => _isListening = false);
    _pulseCtrl.stop();
    _floatCtrl.stop();
    if (text.isNotEmpty) {
      _send(forced: text);
    }
    _liveTranscript = '';
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    _sendCtrl.dispose();
    _speech.stop();
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
    if (_isListening) {
      try { await _speech.stop(); } catch (_) {}
      setState(() => _isListening = false);
      _pulseCtrl.stop();
      _floatCtrl.stop();
    }
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _messages.add({'text': text, 'user': true, 'time': DateTime.now()});
      _controller.clear();
      _liveTranscript = '';
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

  int _micRetryCount = 0;
  DateTime? _micStartTime;

  Future<void> _toggleMic() async {
    if (_isLoading) return;
    if (_isListening) {
      try { await _speech.stop(); } catch (_) {}
      _finishListening();
      return;
    }
    if (!_voiceSupported) return;
    await _startMic();
  }

  Future<void> _startMic({bool isRetry = false}) async {
    if (!isRetry) _micRetryCount = 0;

    try { await _speech.stop(); } catch (_) {}
    if (kIsWeb) await Future.delayed(const Duration(milliseconds: 300));

    _micStartTime = DateTime.now();

    setState(() {
      _isListening = true;
      if (!isRetry) _liveTranscript = '';
      _errorMessage = null;
    });
    _pulseCtrl.repeat(reverse: true);
    _floatCtrl.repeat();

    debugPrint('STT(chat): listen retry=$isRetry attempt=${_micRetryCount + 1}');

    try {
      await _speech.listen(
        localeId: kIsWeb ? 'vi-VN' : 'vi_VN',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          autoPunctuation: true,
          listenMode: ListenMode.dictation,
        ),
        onResult: (r) {
          if (!mounted) return;
          final w = r.recognizedWords.trim();
          debugPrint('STT(chat): result "${w.length > 30 ? '${w.substring(0, 30)}...' : w}" final=${r.finalResult}');
          if (w.isNotEmpty) {
            setState(() => _liveTranscript = w);
          }
          if (r.finalResult && w.isNotEmpty) {
            _finishListening();
          }
        },
      );
    } catch (_) {
      if (mounted) _finishListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Column(
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
        ),
        if (_isListening) _voiceFloatingOverlay(),
      ],
    );
  }

  Widget _voiceFloatingOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80,
      child: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseCtrl, _floatCtrl]),
          builder: (context, child) {
            final floatY = math.sin(_floatCtrl.value * 2 * math.pi) * 6;
            return Transform.translate(
              offset: Offset(0, floatY),
              child: Container(
                width: 320,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2A1E).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Color.lerp(
                      const Color(0xFF22C55E),
                      const Color(0xFF4ADE80),
                      _pulseCtrl.value,
                    )!,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E)
                          .withValues(alpha: 0.15 + 0.2 * _pulseCtrl.value),
                      blurRadius: 28 + 12 * _pulseCtrl.value,
                      spreadRadius: 4 + 6 * _pulseCtrl.value,
                    ),
                    BoxShadow(
                      color: const Color(0xFF14B8A6)
                          .withValues(alpha: 0.08 + 0.1 * _pulseCtrl.value),
                      blurRadius: 50,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _animatedMicIcon(),
                        const SizedBox(width: 10),
                        const Text(
                          'Đang lắng nghe...',
                          style: TextStyle(
                            color: Color(0xFF4ADE80),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _toggleMic,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCA5A5).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.stop_rounded,
                                  color: Color(0xFFFCA5A5), size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_liveTranscript.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF113528),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2E7D5D)),
                        ),
                        child: Text(
                          _liveTranscript,
                          style: const TextStyle(
                            color: Color(0xFFE6FFF3),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    _waveformBars(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _animatedMicIcon() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final scale = 1.0 + 0.15 * _pulseCtrl.value;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color.lerp(const Color(0xFF4ADE80), const Color(0xFF22C55E), _pulseCtrl.value)!,
                  const Color(0xFF15803D),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.4 + 0.3 * _pulseCtrl.value),
                  blurRadius: 12 + 6 * _pulseCtrl.value,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.mic, color: Colors.white, size: 20),
          ),
        );
      },
    );
  }

  Widget _waveformBars() {
    return AnimatedBuilder(
      animation: _floatCtrl,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(12, (i) {
              final phase = _floatCtrl.value * 2 * math.pi + i * 0.5;
              final h = 6.0 + 12.0 * ((math.sin(phase) + 1) / 2);
              return Container(
                width: 3,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: Color.lerp(
                    const Color(0xFF15803D),
                    const Color(0xFF4ADE80),
                    (math.sin(phase) + 1) / 2,
                  ),
                ),
              );
            }),
          ),
        );
      },
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
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A2018), Color(0xFF123729)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isListening ? const Color(0xFF4ADE80) : const Color(0xFF2E7D5D),
          width: _isListening ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isListening
                ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                : const Color(0xFF16A34A).withValues(alpha: 0.25),
            blurRadius: _isListening ? 28 : 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: (_isLoading || !_voiceSupported) ? null : _toggleMic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening
                      ? const Color(0xFF22C55E).withValues(alpha: 0.25)
                      : Colors.transparent,
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF34D399),
                ),
              ),
            ),
          ),
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
                hintText: 'Nhập câu hỏi hoặc bấm mic...',
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
