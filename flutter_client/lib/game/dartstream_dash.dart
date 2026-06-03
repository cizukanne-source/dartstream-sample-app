import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gameplay configuration derived from live DartStream services:
/// - feature flags toggle the rules (double score, hard mode, extra life),
/// - inventory grants the sword ability (clear bombs),
/// - a cloud-save snapshot resumes the high score / lifetime coins.
class DashConfig {
  const DashConfig({
    this.startLives = 3,
    this.doubleScore = false,
    this.hardMode = false,
    this.swordCharges = 0,
    this.resumeHighScore = 0,
    this.resumeLifetimeCoins = 0,
    this.playerName = 'Player',
  });

  final int startLives;
  final bool doubleScore;
  final bool hardMode;
  final int swordCharges;
  final int resumeHighScore;
  final int resumeLifetimeCoins;
  final String playerName;
}

/// "DartStream Dash" — move the ship, catch coins, dodge bombs. Every gameplay
/// beat is wired to a DartStream service via [onSnapshot] (cloud-save) and
/// [onEvent] (reactive event log).
class DartstreamDashGame extends FlameGame
    with HasCollisionDetection, TapCallbacks, DragCallbacks, KeyboardEvents {
  DartstreamDashGame({
    required this.config,
    required this.onSnapshot,
    required this.onEvent,
  });

  final DashConfig config;
  final void Function(Map<String, dynamic> snapshot) onSnapshot;
  final void Function(String type, Map<String, dynamic> payload) onEvent;

  late Player player;
  int score = 0;
  int level = 1;
  int coins = 0;
  int lives = 3;
  int highScore = 0;
  int lifetimeCoins = 0;
  int swordCharges = 0;
  bool gameOver = false;

  final _rng = math.Random();
  double _spawnTimer = 0;

  TextComponent? _hud;
  TextComponent? _modHud;
  TextComponent? _banner;

  double get _fallSpeed => (config.hardMode ? 185 : 135) + (level - 1) * 22;
  double get _spawnInterval =>
      math.max(0.45, (config.hardMode ? 0.8 : 1.0) - (level - 1) * 0.05);
  double get _bombChance => config.hardMode ? 0.42 : 0.28;

  @override
  Color backgroundColor() => const Color(0xFF0E1320);

  @override
  Future<void> onLoad() async {
    lives = config.startLives;
    highScore = config.resumeHighScore;
    lifetimeCoins = config.resumeLifetimeCoins;
    swordCharges = config.swordCharges;

    player = Player()..position = Vector2(size.x / 2, size.y - 56);
    add(player);

    _hud = TextComponent(
      position: Vector2(12, 12),
      textRenderer: _text(16, const Color(0xFFFFFFFF), FontWeight.w700),
    );
    add(_hud!);
    _modHud = TextComponent(
      anchor: Anchor.topRight,
      position: Vector2(size.x - 12, 12),
      textRenderer: _text(12, const Color(0xFF8BA0C8)),
    );
    add(_modHud!);

    _updateHud();
    onEvent('game.start', {
      'player': config.playerName,
      'doubleScore': config.doubleScore,
      'hardMode': config.hardMode,
      'startLives': lives,
      'swordCharges': swordCharges,
    });
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      player.position.y = size.y - 56;
      _modHud?.position = Vector2(size.x - 12, 12);
      _banner?.position = size / 2;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameOver) return;
    _spawnTimer += dt;
    if (_spawnTimer >= _spawnInterval) {
      _spawnTimer = 0;
      _spawn();
    }
  }

  void _spawn() {
    final isBomb = _rng.nextDouble() < _bombChance;
    final x = 24 + _rng.nextDouble() * (size.x - 48);
    add(Faller(isBomb: isBomb, speed: _fallSpeed)..position = Vector2(x, -24));
  }

  void collectCoin(Faller f) {
    if (gameOver) return;
    f.removeFromParent();
    score += config.doubleScore ? 20 : 10;
    coins += 1;
    lifetimeCoins += 1;
    if (score > highScore) highScore = score;
    if (coins % 10 == 0) {
      level += 1;
      onEvent('game.level.up', {'level': level, 'score': score});
    }
    _updateHud();
    _emitSnapshot();
  }

  void hitBomb(Faller f) {
    if (gameOver) return;
    f.removeFromParent();
    lives -= 1;
    onEvent('game.bomb.hit', {'livesLeft': lives, 'score': score});
    _updateHud();
    if (lives <= 0) _endGame();
  }

  void useSword() {
    if (gameOver || swordCharges <= 0) return;
    final bombs = children.whereType<Faller>().where((f) => f.isBomb).toList();
    if (bombs.isEmpty) return;
    for (final b in bombs) {
      b.removeFromParent();
    }
    swordCharges -= 1;
    onEvent('game.sword.used', {'cleared': bombs.length, 'left': swordCharges});
    _updateHud();
  }

  void _endGame() {
    gameOver = true;
    for (final f in children.whereType<Faller>().toList()) {
      f.removeFromParent();
    }
    _banner = TextComponent(
      text: 'GAME OVER\nScore $score · High $highScore\ntap / R to play again',
      anchor: Anchor.center,
      position: size / 2,
      textRenderer: _text(22, const Color(0xFFFFFFFF), FontWeight.w800),
    );
    add(_banner!);
    onEvent('game.over', {
      'score': score,
      'highScore': highScore,
      'level': level,
      'coins': coins,
      'lifetimeCoins': lifetimeCoins,
    });
    _emitSnapshot();
  }

  void _restart() {
    if (!gameOver) return;
    _banner?.removeFromParent();
    _banner = null;
    score = 0;
    coins = 0;
    level = 1;
    lives = config.startLives;
    swordCharges = config.swordCharges;
    gameOver = false;
    player.position = Vector2(size.x / 2, size.y - 56);
    _updateHud();
    onEvent('game.start', {'player': config.playerName, 'restart': true});
  }

  void _emitSnapshot() {
    onSnapshot({
      'score': score,
      'highScore': highScore,
      'level': level,
      'lives': lives,
      'coins': coins,
      'lifetimeCoins': lifetimeCoins,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _updateHud() {
    _hud?.text = 'Score $score   Lv $level   ♥ ${'♥' * math.max(0, lives - 1)}'
        '($lives)\nHigh $highScore   Coins $lifetimeCoins';
    final mods = <String>[
      if (config.doubleScore) '2× score',
      if (config.hardMode) 'hard',
    ];
    _modHud?.text = [
      config.playerName,
      if (mods.isNotEmpty) 'flags: ${mods.join(', ')}',
      if (swordCharges > 0) 'sword ×$swordCharges (space)',
    ].join('\n');
  }

  TextPaint _text(double size, Color color, [FontWeight w = FontWeight.w500]) =>
      TextPaint(style: TextStyle(color: color, fontSize: size, fontWeight: w));

  // ---- input -------------------------------------------------------------

  @override
  void onTapDown(TapDownEvent event) {
    if (gameOver) {
      _restart();
    } else {
      useSword();
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (gameOver) return;
    player.moveBy(event.localDelta.x);
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (gameOver) {
      if (event is KeyDownEvent &&
          (keysPressed.contains(LogicalKeyboardKey.enter) ||
              keysPressed.contains(LogicalKeyboardKey.keyR) ||
              keysPressed.contains(LogicalKeyboardKey.space))) {
        _restart();
      }
      return KeyEventResult.handled;
    }
    final left = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    final right = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);
    player.vx = (right ? 280.0 : 0) - (left ? 280.0 : 0);
    if (event is KeyDownEvent && keysPressed.contains(LogicalKeyboardKey.space)) {
      useSword();
    }
    return KeyEventResult.handled;
  }
}

class Player extends PositionComponent
    with HasGameReference<DartstreamDashGame>, CollisionCallbacks {
  Player() : super(size: Vector2(46, 30), anchor: Anchor.center);

  double vx = 0;

  void moveBy(double dx) {
    x = (x + dx).clamp(size.x / 2, game.size.x - size.x / 2);
  }

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    if (vx != 0) {
      x = (x + vx * dt).clamp(size.x / 2, game.size.x - size.x / 2);
    }
  }

  @override
  void render(Canvas canvas) {
    final path = Path()
      ..moveTo(size.x / 2, 0)
      ..lineTo(size.x, size.y)
      ..lineTo(0, size.y)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF3DBEFF));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFBDEBFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Faller) {
      if (other.isBomb) {
        game.hitBomb(other);
      } else {
        game.collectCoin(other);
      }
    }
  }
}

class Faller extends PositionComponent with CollisionCallbacks {
  Faller({required this.isBomb, required this.speed})
      : super(size: Vector2.all(isBomb ? 32 : 26), anchor: Anchor.center);

  final bool isBomb;
  final double speed;

  @override
  Future<void> onLoad() async {
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    y += speed * dt;
    final game = findGame();
    if (game != null && y > game.size.y + 40) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final r = size.x / 2;
    final c = Offset(r, r);
    if (isBomb) {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE5484D));
      canvas.drawCircle(c, r * 0.55, Paint()..color = const Color(0xFF7A1115));
    } else {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFC857));
      canvas.drawCircle(c, r * 0.62, Paint()..color = const Color(0xFFD99B2A));
    }
  }
}
