import 'package:flutter/material.dart';

import 'editor_screen.dart';

class LocodeSplashScreen extends StatefulWidget {
  const LocodeSplashScreen({super.key});

  @override
  State<LocodeSplashScreen> createState() => _LocodeSplashScreenState();
}

class _LocodeSplashScreenState extends State<LocodeSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  String _status = "Initializing...";

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic)),
    );

    _controller.forward();
    _startEverything();
  }

  Future<void> _startEverything() async {
    // 1. Short delay for style
    setState(() => _status = "Systems Ready");
    await Future.delayed(const Duration(milliseconds: 1500));

    // 2. Short delay for style
    setState(() => _status = "Systems Ready");
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (_, __, ___) => const EditorScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sleek dark background to match the new professional theme
    const Color bgDark = Color(0xFF0A0A0A);
    const Color iconColor = Color(0xFFF8F8F8);
    const Color brandBlue = Color(0xFF3B82F6);

    return Scaffold(
      backgroundColor: bgDark,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Core Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: brandBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: brandBlue.withOpacity(0.2), width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 64,
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Typographic Logo
                    const Text(
                      'LOCODE',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 6.0,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ON-DEVICE CODING ENGINE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.5,
                        color: Colors.white30,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      _status.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
