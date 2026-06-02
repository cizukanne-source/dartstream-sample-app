import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// Minimal "tap to score" Flame game. One pulsing coin in the middle; any tap
/// on the canvas increments the score. `onScore` fires every tap so the host
/// can debounce a cloud-save write. `onMilestone` fires at every multiple of
/// `milestoneEvery` (default 10) so the host can log a reactive event.
class TapToScoreGame extends FlameGame with TapCallbacks {
  TapToScoreGame({
    required int initialScore,
    required this.onScore,
    required this.onMilestone,
    this.milestoneEvery = 10,
  }) : score = initialScore;

  int score;
  final void Function(int score) onScore;
  final void Function(int score) onMilestone;
  final int milestoneEvery;

  final _Coin _coin = _Coin();
  TextComponent? _scoreText;
  TextComponent? _hintText;

  @override
  Color backgroundColor() => const Color(0xFF101522);

  @override
  Future<void> onLoad() async {
    _coin.position = size / 2;
    add(_coin);

    _scoreText = TextComponent(
      text: 'Score: $score',
      anchor: Anchor.topCenter,
      position: Vector2(size.x / 2, 16),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    add(_scoreText!);

    _hintText = TextComponent(
      text: 'Tap anywhere to score',
      anchor: Anchor.bottomCenter,
      position: Vector2(size.x / 2, size.y - 16),
      textRenderer: TextPaint(
        style: const TextStyle(color: Color(0xFF7C8CB8), fontSize: 13),
      ),
    );
    add(_hintText!);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _coin.position = size / 2;
    _scoreText?.position = Vector2(size.x / 2, 16);
    _hintText?.position = Vector2(size.x / 2, size.y - 16);
  }

  @override
  void onTapDown(TapDownEvent event) {
    score += 1;
    _scoreText?.text = 'Score: $score';
    _coin.pulse();
    onScore(score);
    if (score > 0 && score % milestoneEvery == 0) {
      onMilestone(score);
    }
  }
}

class _Coin extends PositionComponent {
  _Coin() : super(size: Vector2.all(80), anchor: Anchor.center);

  double _scale = 1;

  void pulse() => _scale = 1.25;

  @override
  void update(double dt) {
    super.update(dt);
    _scale += (1.0 - _scale) * math.min(1.0, dt * 8);
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final radius = (size.x / 2) * _scale;
    final glow = Paint()
      ..color = const Color(0xFFFFB454).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(cx, cy), radius + 8, glow);
    final body = Paint()..color = const Color(0xFFFFC857);
    canvas.drawCircle(Offset(cx, cy), radius, body);
    final inner = Paint()..color = const Color(0xFFD99B2A);
    canvas.drawCircle(Offset(cx, cy), radius * 0.7, inner);
    final tp = TextPainter(
      text: TextSpan(
        text: '\$',
        style: TextStyle(
          color: const Color(0xFF422C00),
          fontSize: radius,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }
}
