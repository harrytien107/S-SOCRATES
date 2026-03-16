import 'package:flutter/material.dart';

import 'text_chat_tab.dart';
import 'voice_chat_tab.dart';

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
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Column(
                    children: [
                      _header(),
                      const SizedBox(height: 10),
                      _tabBar(),
                      const SizedBox(height: 6),
                      Expanded(
                        child: TabBarView(
                          controller: _tabCtrl,
                          children: const [
                            TextChatTab(),
                            VoiceChatTab(),
                          ],
                        ),
                      ),
                      _footer(),
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

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              color: const Color(0xFF0D3427),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo_spinner.png', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'S-Socrates AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'UTH - Chiến thần phản biện',
                  style: TextStyle(color: Color(0xFFD1FAE5), fontSize: 12.5),
                ),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
              color: const Color(0xFF0D3427),
            ),
            child: const Icon(Icons.school_rounded, color: Color(0xFF4ADE80), size: 22),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Container(
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
    );
  }

  Widget _footer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      margin: const EdgeInsets.only(bottom: 6, top: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        'S-Socrates AI Chat - Trường Đại học Giao thông Vận tải TP.HCM (UTH)',
        textAlign: TextAlign.center,
        style:
            TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
      ),
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
