import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// One launch-only animation; the destination stays mounted during the reveal.
class LaunchSplash extends StatefulWidget {
  final Widget child;
  const LaunchSplash({super.key, required this.child});

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ImageStream? _stream;
  late final ImageStreamListener _listener;
  ImageInfo? _logo;
  bool _started = false;
  bool _finished = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200),
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _finished = true);
        }
      });
    _listener = ImageStreamListener((info, _) {
      if (!mounted) {
        info.dispose();
        return;
      }
      setState(() {
        _logo?.dispose();
        _logo = info;
      });
      if (!_controller.isAnimating && !_finished) _controller.forward();
    }, onError: (Object error, StackTrace? stack) {
      // Still reveal the destination if branding cannot be loaded.
      if (mounted && !_controller.isAnimating && !_finished) _controller.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _stream = const AssetImage('assets/tubig_connect_logo.png')
        .resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _logo?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final reveal = const Interval(0.82, 1, curve: Curves.easeInOut)
            .transform(_controller.value);
        return Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Color(0xFFF9FDFF)),
          ExcludeSemantics(
            child: IgnorePointer(
              child: Opacity(opacity: reveal, child: child),
            ),
          ),
          Opacity(
            opacity: 1 - reveal,
            child: Semantics(
              label: 'TubigConnect.',
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SplashPainter(
                    _logo?.image, _controller.value, _reduceMotion,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class _SplashPainter extends CustomPainter {
  final ui.Image? logo;
  final double progress;
  final bool reduceMotion;
  _SplashPainter(this.logo, this.progress, this.reduceMotion);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFFCDEEFF), Color(0xFFF9FDFF), Color(0xFFBCE7FC)],
      stops: [0, 0.48, 1],
    ).createShader(bounds));

    // Broad translucent waves echo the supplied artwork.
    for (var i = 0; i < 3; i++) {
      final drift = reduceMotion ? 0.0 : math.sin(progress * math.pi) * 18;
      final y = size.height * (0.87 + i * 0.035);
      final wave = Path()
        ..moveTo(0, y)
        ..cubicTo(size.width * 0.3, y - 65 + drift,
            size.width * 0.5, y + 100, size.width, y - 50)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(wave, Paint()
        ..color = [const Color(0x55FFFFFF), const Color(0x3395D9FA),
          const Color(0x4483D2F6)][i]);
    }

    final image = logo;
    if (image == null) return;
    final extent = math.min(440.0, math.min(size.width * 0.87, size.height * 0.60));
    final target = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: extent, height: extent * image.height / image.width,
    );
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final source = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    if (reduceMotion || progress >= 0.72) {
      paint.color = Colors.white.withValues(alpha: reduceMotion
          ? const Interval(0, 0.5).transform(progress) : 1);
      canvas.drawImageRect(image, source, target, paint);
      return;
    }

    // Every fragment samples the original asset: the final logo is unchanged.
    const columns = 5;
    const rows = 5;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final delay = ((col * 3 + row * 7) % 9) * 0.018;
        final t = ((progress - 0.035 - delay) / 0.49).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(t);
        final remaining = 1 - eased;
        final piece = Rect.fromLTWH(
          target.left + col * target.width / columns,
          target.top + row * target.height / rows,
          target.width / columns, target.height / rows,
        );
        final src = Rect.fromLTWH(
          col * source.width / columns, row * source.height / rows,
          source.width / columns, source.height / rows,
        );
        final direction = Offset((col - 2) * 29.0, (row - 2) * 24.0);
        canvas.save();
        canvas.translate(piece.center.dx + direction.dx * remaining,
            piece.center.dy + direction.dy * remaining);
        canvas.rotate(((row + col).isEven ? 1 : -1) * 0.13 * remaining);
        paint.color = Colors.white.withValues(alpha: Curves.easeIn.transform(t));
        canvas.drawImageRect(image, src,
            Rect.fromCenter(center: Offset.zero, width: piece.width, height: piece.height),
            paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_SplashPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.logo != logo ||
      oldDelegate.reduceMotion != reduceMotion;
}
