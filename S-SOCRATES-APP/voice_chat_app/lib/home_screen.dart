import 'package:flutter/material.dart';

import 'text_chat_tab.dart';
import 'voice_chat_tab.dart';
import 'package:voice_chat_app/services/api_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _fxPulse = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _fxPulse = true);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _openGuide() {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0B2A20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hướng dẫn sử dụng',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Tab Chat AI:\n'
                '  - Nhập câu hỏi rồi bấm Gửi.\n'
                '  - Bấm mic để nói, text sẽ điền vào ô nhập.\n\n'
                'Tab Voice AI:\n'
                '  - Bấm nút mic lớn để nói.\n'
                '  - AI sẽ phản hồi bằng cả text và giọng nói.\n\n',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88), height: 1.55),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openIpConfig() {
    final ctrl = TextEditingController(text: ApiConfig.baseUrl);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B2A20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cấu hình Backend', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'API Base URL',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            // enabledBorder: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            hintText: 'http://192.168.x.x:8000',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            onPressed: () async {
              await ApiConfig.setBaseUrl(ctrl.text.trim());
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Lưu', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pageGradient = LinearGradient(
      colors: [Color(0xFF061A12), Color(0xFF0F3A2A), Color(0xFF155E3E)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: pageGradient)),
          _bgFx(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Column(
                    children: [
                      _tabBar(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          controller: _tabCtrl,
                          children: const [
                            TextChatTab(),
                            VoiceChatTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _openGuide,
                child: Ink(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.question_mark_rounded,
                      size: 17, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            padding: const EdgeInsets.all(3),
            child: TabBar(
              controller: _tabCtrl,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF34D399)),
              ),
              splashBorderRadius: BorderRadius.circular(11),
              overlayColor: WidgetStateProperty.all(
                const Color(0xFF22C55E).withValues(alpha: 0.08),
              ),
              dividerColor: Colors.transparent,
              labelColor: const Color(0xFF4ADE80),
              unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Chat AI'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Voice AI'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _openIpConfig,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: const Icon(Icons.settings_rounded, color: Color(0xFF34D399), size: 24),
          ),
        ),
      ],
    );
  }

  Widget _bgFx() {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: _fxPulse ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeInOut,
        builder: (_, t, child) => Stack(
          children: [
            Positioned(
              left: -120 + 24 * t,
              top: -90 + 16 * t,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF22C55E)
                      .withValues(alpha: 0.14 + 0.08 * t),
                ),
              ),
            ),
            Positioned(
              right: -130 + 18 * t,
              bottom: -110 + 24 * t,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF14B8A6)
                      .withValues(alpha: 0.12 + 0.08 * t),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
