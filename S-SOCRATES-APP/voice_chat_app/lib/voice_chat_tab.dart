import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'mic_glow.dart';
import 'services/agent_api.dart';
import 'services/text_to_speak.dart';
import 'widgets/chat_bubble.dart';

class VoiceChatTab extends StatefulWidget {
  const VoiceChatTab({super.key});

  @override
  State<VoiceChatTab> createState() => _VoiceChatTabState();
}

class _VoiceChatTabState extends State<VoiceChatTab>
    with AutomaticKeepAliveClientMixin {
  final AgentAPI _api = AgentAPI();
  final SpeechToText _speech = SpeechToText();
  final ScrollController _scroll = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _isVoiceStarting = false;
  bool _voiceSupported = false;
  bool _showOverlay = false;
  bool _isSpeakingTTS = false;
  int _sessionSeed = 0;
  int? _activeSessionId;
  bool _autoSentThisSession = false;
  String _liveTranscript = '';
  String? _errorMessage;

  int _retryCount = 0;
  DateTime? _sessionStartTime;
  static const int _maxRetries = 3;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'text':
          'Xin chào! Bấm nút mic bên dưới để bắt đầu trò chuyện bằng giọng nói.',
      'user': false,
      'time': DateTime.now(),
    });
    _initSpeech();
    _initTTSListeners();
  }

  void _initTTSListeners() {
    setTTSCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeakingTTS = false;
        for (final m in _messages) {
          if (m['speaking'] == true) m['speaking'] = false;
        }
      });
      // Auto-listen after AI finishes speaking for natural conversation flow
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_isLoading && !_isListening && _activeSessionId == null) {
          _startSession();
        }
      });
    });
    setTTSCancelHandler(() {
      // User manually stopped TTS -- don't auto-listen
      if (!mounted) return;
      setState(() {
        _isSpeakingTTS = false;
        for (final m in _messages) {
          if (m['speaking'] == true) m['speaking'] = false;
        }
      });
    });
  }

  Future<void> _stopTTS() async {
    await stopSpeaking();
    if (!mounted) return;
    setState(() {
      _isSpeakingTTS = false;
      for (final m in _messages) {
        if (m['speaking'] == true) m['speaking'] = false;
      }
    });
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
    );
    debugPrint('STT: initialize ok=$ok');
    if (mounted) setState(() => _voiceSupported = ok);
  }

  bool _isActive(int id) => _activeSessionId == id;

  void _onStatus(String status) {
    if (!mounted || _activeSessionId == null) return;
    debugPrint('STT: status="$status" sid=$_activeSessionId');
    final n = status.toLowerCase().replaceAll('_', '').replaceAll(' ', '');
    if (n == 'listening') {
      setState(() {
        _isVoiceStarting = false;
        _isListening = true;
        _showOverlay = true;
      });
      return;
    }
    if (n == 'done' || n == 'notlistening') {
      final sid = _activeSessionId;
      if (sid == null) return;
      unawaited(_handleStop(sid));
    }
  }

  Future<void> _handleStop(int sid) async {
    if (!_isActive(sid)) return;
    final transcript = _liveTranscript.trim();
    final elapsed = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inMilliseconds
        : 0;

    debugPrint(
        'STT: handleStop sid=$sid elapsed=${elapsed}ms '
        'transcript="${transcript.length > 30 ? '${transcript.substring(0, 30)}...' : transcript}"');

    _activeSessionId = null;

    if (_autoSentThisSession || _isLoading) {
      setState(() {
        _isVoiceStarting = false;
        _isListening = false;
        _showOverlay = false;
      });
      return;
    }

    // Auto-retry if session ended too quickly with no transcript (browser flake)
    if (transcript.isEmpty && elapsed < 2000 && _retryCount < _maxRetries) {
      _retryCount++;
      debugPrint('STT: Quick fail (${elapsed}ms), auto-retry #$_retryCount/$_maxRetries');
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted && !_isLoading && !_autoSentThisSession) {
        await _startSession(isRetry: true);
        return;
      }
    }

    setState(() {
      _isVoiceStarting = false;
      _isListening = false;
      _showOverlay = false;
    });

    if (transcript.isEmpty) {
      if (mounted) {
        setState(() => _errorMessage =
            'Không thu được giọng nói. Hãy nói rõ hơn hoặc kiểm tra quyền mic.');
      }
      return;
    }

    _autoSentThisSession = true;
    await _send(transcript);
  }

  void _onError(dynamic error) {
    debugPrint('STT: error=$error');
    final sid = _activeSessionId;
    _activeSessionId = null;
    if (!mounted) return;

    final elapsed = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inMilliseconds
        : 0;

    // Auto-retry on quick errors (browser flake)
    if (elapsed < 2000 && _retryCount < _maxRetries && sid != null) {
      _retryCount++;
      debugPrint('STT: Error during quick session, auto-retry #$_retryCount/$_maxRetries');
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_isLoading && !_autoSentThisSession) {
          _startSession(isRetry: true);
        }
      });
      return;
    }

    setState(() {
      _isVoiceStarting = false;
      _isListening = false;
      _showOverlay = false;
      _errorMessage = 'Mic gặp lỗi. Hãy cấp quyền microphone và thử lại.';
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
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

  Future<void> _send(String text) async {
    if (text.isEmpty || _isLoading) return;
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _messages.add({'text': text, 'user': true, 'time': DateTime.now()});
    });
    _scrollDown();
    try {
      final reply = await _api.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _messages.add({
          'text': reply,
          'user': false,
          'time': DateTime.now(),
          'speaking': true,
        });
        _isSpeakingTTS = true;
      });
      _scrollDown();
      await speak(reply);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyErr(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyErr(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('timeout')) return 'Backend phản hồi quá lâu.';
    if (m.contains('failed to fetch') || m.contains('clientexception')) {
      return 'Không kết nối được backend.';
    }
    return 'Có lỗi khi gửi tin nhắn.';
  }

  Future<void> _startSession({bool isRetry = false}) async {
    if (_isLoading || _isSpeakingTTS) return;
    if (!isRetry) {
      if (_isVoiceStarting || _isListening || _activeSessionId != null) return;
      _retryCount = 0;
    }

    if (!_voiceSupported) {
      final ok = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
      _voiceSupported = ok;
      if (!ok) {
        if (mounted) setState(() => _errorMessage = 'Không thể bật mic.');
        return;
      }
    }

    // Stop previous + delay so browser releases mic properly
    try {
      await _speech.stop();
    } catch (_) {}
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final sid = ++_sessionSeed;
    _activeSessionId = sid;
    _autoSentThisSession = false;
    _sessionStartTime = DateTime.now();

    setState(() {
      _isVoiceStarting = true;
      _isListening = false;
      _showOverlay = true;
      if (!isRetry) _liveTranscript = '';
      _errorMessage = null;
    });

    debugPrint('STT: listen() sid=$sid retry=$isRetry attempt=${_retryCount + 1}');

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
        onResult: (r) async {
          if (!mounted || !_isActive(sid)) return;
          final w = r.recognizedWords.trim();
          debugPrint('STT: result "${w.length > 40 ? '${w.substring(0, 40)}...' : w}" final=${r.finalResult}');
          if (w.isNotEmpty) setState(() => _liveTranscript = w);

          if (r.finalResult &&
              w.isNotEmpty &&
              !_autoSentThisSession &&
              !_isLoading &&
              _isActive(sid)) {
            _autoSentThisSession = true;
            _activeSessionId = null;
            try {
              await _speech.stop();
            } catch (_) {}
            if (!mounted) return;
            setState(() {
              _isListening = false;
              _isVoiceStarting = false;
              _showOverlay = false;
            });
            await _send(w);
          }
        },
      );
    } catch (e) {
      debugPrint('STT: listen() threw: $e');
      if (!_isActive(sid)) return;
      _activeSessionId = null;
      if (!mounted) return;
      setState(() {
        _isVoiceStarting = false;
        _isListening = false;
        _showOverlay = false;
        _errorMessage = 'Không thể bật mic lúc này.';
      });
      return;
    }

    if (!mounted || !_isActive(sid)) return;
    setState(() {
      _isVoiceStarting = false;
      _isListening = true;
      _showOverlay = true;
    });
  }

  Future<void> _stopSession() async {
    debugPrint('STT: manual stop');
    // If not listening or starting, reset sid just in case it got stuck
    if (!_isListening && !_isVoiceStarting) {
      _activeSessionId = null;
    }
    
    // Don't clear _activeSessionId yet if we are listening, 
    // let _onStatus -> _handleStop process the final transcript.
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('STT: stop error: $e');
      _activeSessionId = null; // Force clear on error
    }
    if (!mounted) return;
    setState(() {
      _isVoiceStarting = false;
      _isListening = false;
      _showOverlay = false;
    });
  }

  Future<void> _toggleMic() async {
    if (_isLoading) return;
    // More robust toggle: if UI says we are listening or starting, stop it.
    if (_isListening || _isVoiceStarting || _activeSessionId != null) {
      await _stopSession();
      return;
    }
    await _startSession();
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
                      isSpeaking: (m['speaking'] as bool?) ?? false,
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
                  style:
                      const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                ),
              ),
            _micBar(),
          ],
        ),
        if (_showOverlay) _voiceOverlay(),
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

  Widget _micBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A2018), Color(0xFF123729)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2E7D5D)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: (_isLoading ||
                      !_voiceSupported ||
                      _isVoiceStarting ||
                      _isSpeakingTTS)
                  ? null
                  : _toggleMic,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isListening
                        ? [const Color(0xFF4ADE80), const Color(0xFF16A34A)]
                        : [const Color(0xFF22C55E), const Color(0xFF15803D)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.stop_rounded : Icons.mic,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _isListening
                  ? 'Đang lắng nghe...'
                  : _isSpeakingTTS
                      ? 'AI đang đọc phản hồi...'
                      : _isVoiceStarting
                          ? 'Đang kết nối mic...'
                          : 'Bấm mic để nói',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
              ),
            ),
          ),
          if (_isSpeakingTTS)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _stopTTS,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFCA5A5).withValues(alpha: 0.15),
                    border: Border.all(
                      color: const Color(0xFFFCA5A5).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.stop_rounded,
                    color: Color(0xFFFCA5A5),
                    size: 24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _voiceOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {},
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          child: Center(
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A241D),
                borderRadius: BorderRadius.circular(22),
                border:
                    Border.all(color: const Color(0xFF34D399), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isVoiceStarting
                        ? 'Đang kết nối mic...'
                        : 'AI Voice đang lắng nghe',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 160,
                    height: 160,
                    child: FittedBox(child: MicGlow()),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 64),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF113528),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E7D5D)),
                    ),
                    child: Text(
                      _liveTranscript.isEmpty
                          ? (_isVoiceStarting
                              ? 'Đang kết nối...'
                              : 'Bắt đầu nói... nội dung sẽ hiển thị tại đây.')
                          : _liveTranscript,
                      style: TextStyle(
                        color: _liveTranscript.isEmpty
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFE6FFF3),
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_retryCount > 0 && _isVoiceStarting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Đang thử kết nối lại... ($_retryCount/$_maxRetries)',
                        style: TextStyle(
                          color: const Color(0xFFFCD34D).withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: _stopSession,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Dừng lắng nghe'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFCA5A5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
