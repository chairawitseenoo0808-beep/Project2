import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Web Audio interop
// ─────────────────────────────────────────────────────────────────────────────

@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external _AudioContext();
  external double get currentTime;
  external JSObject get destination;
  external String get state;
  external _Oscillator createOscillator();
  external _Gain createGain();
  external JSPromise<JSAny?> resume();
}

@JS()
extension type _AudioParam._(JSObject _) implements JSObject {
  external set value(double v);
  external void setValueAtTime(double value, double time);
  external void exponentialRampToValueAtTime(double value, double time);
}

@JS()
extension type _Oscillator._(JSObject _) implements JSObject {
  external _AudioParam get frequency;
  external set type(String t);
  external void connect(JSObject destination);
  external void start(double when);
  external void stop(double when);
}

@JS()
extension type _Gain._(JSObject _) implements JSObject {
  external _AudioParam get gain;
  external void connect(JSObject destination);
}

@JS('localStorage')
external _Storage get _localStorage;

@JS()
extension type _Storage._(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

/// เสียงเอฟเฟกต์ (chime) + เพลงพื้นหลังเบาๆ สังเคราะห์เองด้วย Web Audio
/// ไม่ต้องใช้ไฟล์เสียงหรือแพ็กเกจเพิ่ม
class ChimePlayer {
  _AudioContext? _ctx;
  bool muted = false; // ปิดเสียงทั้งหมด
  bool musicOn = true; // เปิด/ปิดเฉพาะเพลงพื้นหลัง
  final AudioPlayer _musicPlayer = AudioPlayer();

  // ── เพลงพื้นหลัง ──────────────────────────────────────────────────────────
  /// ความดังเพลง: 0.01 = เบามาก, 0.035 = เบาสบาย, 0.08 = ค่อนข้างดัง
  static const _musicVolume = 0.5;

  /// ความยาวโน้ต 1 ตัว (วินาที) ยิ่งมากยิ่งช้า
  static const _stepLen = 0.5;

  static const _chords = [
    [220.00, 261.63, 329.63], // Am
    [174.61, 220.00, 261.63], // F
    [261.63, 329.63, 392.00], // C
    [196.00, 246.94, 293.66], // G
  ];
  static const _pattern = [0, 1, 2, 1, 0, 1, 2, 1];

  Timer? _musicTimer;
  double _nextNote = 0;
  int _step = 0;

  void unlock() {
    try {
      _ctx ??= _AudioContext();
      if (_ctx!.state != 'running') _ctx!.resume();
    } catch (_) {}
  }

Future<void> startMusic() async {
  if (muted || !musicOn) return;

  await _musicPlayer.setReleaseMode(ReleaseMode.loop);
  await _musicPlayer.play(
    AssetSource('images/audio/The-Avengers.mp3'),
    volume: 0.5,
  );
}

void stopMusic() {
  _musicPlayer.stop();
}

  void _schedule() {
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      while (_nextNote < ctx.currentTime + 0.8) {
        final chord = _chords[(_step ~/ _pattern.length) % _chords.length];
        final pos = _step % _pattern.length;

        // โน้ตทำนอง (arpeggio)
        _toneAt(chord[_pattern[pos]] * 2, _nextNote, 1.4, _musicVolume,
            attack: 0.06);
        // โน้ตเบส ตอนเปลี่ยนคอร์ด
        if (pos == 0) {
          _toneAt(chord[0] * 0.5, _nextNote, 3.6, _musicVolume * 1.2,
              attack: 0.3, overtone: 0);
        }
        _nextNote += _stepLen;
        _step++;
      }
    } catch (_) {}
  }

  // ── เสียงพื้นฐาน ──────────────────────────────────────────────────────────

  void _toneAt(
    double freq,
    double t0,
    double length,
    double peak, {
    double attack = 0.02,
    double overtone = 0.22,
  }) {
    final ctx = _ctx;
    if (ctx == null) return;

    for (final partial in [(1.0, 1.0), (2.0, overtone)]) {
      if (partial.$2 <= 0) continue;
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = freq * partial.$1;
      gain.gain.setValueAtTime(0.0001, t0);
      gain.gain.exponentialRampToValueAtTime(peak * partial.$2, t0 + attack);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + length);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(t0);
      osc.stop(t0 + length + 0.05);
    }
  }

  void _tone(double freq, double delay, double length, double peak) {
    final ctx = _ctx;
    if (ctx == null) return;
    _toneAt(freq, ctx.currentTime + delay, length, peak);
  }

  void match() {
    if (muted) return;
    try {
      _tone(1046.5, 0.00, 0.55, 0.16);
      _tone(1318.5, 0.09, 0.75, 0.16);
    } catch (_) {}
  }

  void win() {
    if (muted) return;
    try {
      _tone(1046.5, 0.00, 0.60, 0.14);
      _tone(1318.5, 0.11, 0.60, 0.14);
      _tone(1568.0, 0.22, 0.60, 0.14);
      _tone(2093.0, 0.33, 1.00, 0.14);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Themes (โทนสีพื้นหลัง/ปุ่ม) และสไตล์พื้นหลังในการ์ด
// ─────────────────────────────────────────────────────────────────────────────

class GameTheme {
  const GameTheme({
    required this.name,
    required this.dark,
    required this.bgTop,
    required this.bgBottom,
    required this.surface,
    required this.line,
    required this.text,
    required this.textDim,
    required this.accent, // สีปุ่มหลัก (Start / Resume)
    required this.onAccent, // สีตัวอักษรบนปุ่มหลัก
    required this.backA, // หลังการ์ด (ไล่สี)
    required this.backB,
    required this.backMark, // วงกลมกลางหลังการ์ด
    required this.shadow,
  });

  final String name;
  final bool dark;
  final Color bgTop, bgBottom, surface, line, text, textDim;
  final Color accent, onAccent, backA, backB, backMark, shadow;
}

const _themes = [
  GameTheme(
    name: 'Midnight',
    dark: true,
    bgTop: Color(0xFF1B2440),
    bgBottom: Color(0xFF0E1426),
    surface: Color(0xFF222C4A),
    line: Color(0xFF33406A),
    text: Color(0xFFF1F3FA),
    textDim: Color(0xFF8F9AC0),
    accent: Color(0xFFE23636),
    onAccent: Color(0xFFFFFFFF),
    backA: Color(0xFF2B3866),
    backB: Color(0xFF1D2749),
    backMark: Color(0xFFE86A6A),
    shadow: Color(0xFF000000),
  ),
  GameTheme(
    name: 'Cream',
    dark: false,
    bgTop: Color(0xFFFAF6EC),
    bgBottom: Color(0xFFF2EBDB),
    surface: Color(0xFFFFFCF5),
    line: Color(0xFFE6DDCB),
    text: Color(0xFF3A342C),
    textDim: Color(0xFF9C9384),
    accent: Color(0xFF4A433A),
    onAccent: Color(0xFFF8F3E8),
    backA: Color(0xFFEFE6D4),
    backB: Color(0xFFE5D9C2),
    backMark: Color(0xFFB9AA90),
    shadow: Color(0xFF6B5B3E),
  ),
  GameTheme(
    name: 'Sky',
    dark: false,
    bgTop: Color(0xFFEAF3FF),
    bgBottom: Color(0xFFD6E6FA),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFC4D7F0),
    text: Color(0xFF1F2A44),
    textDim: Color(0xFF6F7FA0),
    accent: Color(0xFFD93636),
    onAccent: Color(0xFFFFFFFF),
    backA: Color(0xFFDCE8F8),
    backB: Color(0xFFC6D8F0),
    backMark: Color(0xFF7F9CCB),
    shadow: Color(0xFF3B5A8C),
  ),
  GameTheme(
    name: 'Charcoal',
    dark: true,
    bgTop: Color(0xFF2A2A2E),
    bgBottom: Color(0xFF151518),
    surface: Color(0xFF323237),
    line: Color(0xFF45454C),
    text: Color(0xFFF5F5F7),
    textDim: Color(0xFF9A9AA3),
    accent: Color(0xFFF2B84B),
    onAccent: Color(0xFF2A2A2E),
    backA: Color(0xFF3A3A40),
    backB: Color(0xFF28282D),
    backMark: Color(0xFFF2B84B),
    shadow: Color(0xFF000000),
  ),
];

class CardFace {
  const CardFace(this.name, this.color);
  final String name;
  final Color? color; // null = สีตามตัวละคร (ใช้ tints)
}

/// ตัวเลือกพื้นหลังภายในการ์ด (ด้านที่เปิดรูป)
const _faces = [
  CardFace('White', Color(0xFFFFFFFF)),
  CardFace('Per character', null),
  CardFace('Cream', Color(0xFFFFF1D6)),
  CardFace('Ice blue', Color(0xFFDCE8FA)),
  CardFace('Dark', Color(0xFF1E2230)),
];

class _C {
  static const matchFill = Color(0xFFCDEBD3);
  static const matchLine = Color(0xFF6DB383);
  static const radius = 16.0;

  static const fontFallback = [
    '-apple-system',
    'BlinkMacSystemFont',
    'SF Pro Display',
    'Helvetica Neue',
    'Roboto',
  ];
  static const emojiFallback = [
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Color Emoji',
  ];
}

Widget _asset(String path, double size, Color fallback) {
  return Image.asset(
    path,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, __, ___) =>
        Icon(Icons.broken_image_outlined, size: size * 0.6, color: fallback),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

enum Phase { idle, playing, paused, won }

class MemCard {
  MemCard(this.symbol);
  final int symbol;
  bool faceUp = false;
  bool success = false;
  bool matched = false;
}

/// คะแนนของผู้เล่น 1 รอบ: เรียงตามจำนวนครั้งที่กด (น้อยชนะ)
/// ถ้าเท่ากันให้ดูเวลา (เร็วกว่าชนะ)
class ScoreEntry {
  const ScoreEntry(this.name, this.moves, this.ms, this.at);

  final String name;
  final int moves;
  final int ms; // เวลาที่ใช้ (มิลลิวินาที)
  final int at; // เวลาที่เล่นจบ (epoch ms)

  Map<String, dynamic> toJson() =>
      {'name': name, 'moves': moves, 'ms': ms, 'at': at};

  factory ScoreEntry.fromJson(Map<String, dynamic> j) => ScoreEntry(
        j['name'] as String,
        j['moves'] as int,
        j['ms'] as int,
        j['at'] as int,
      );

  static int compare(ScoreEntry a, ScoreEntry b) {
    final byMoves = a.moves.compareTo(b.moves);
    return byMoves != 0 ? byMoves : a.ms.compareTo(b.ms);
  }
}

/// เวลาเป็นวินาทีเต็ม เช่น "42 วินาที" (การจัดอันดับยังเทียบเป็นมิลลิวินาที)
String _fmtSec(int ms) => '${ms ~/ 1000} วินาที';

// ─────────────────────────────────────────────────────────────────────────────
// App
// ─────────────────────────────────────────────────────────────────────────────

void main() => runApp(const MemoryApp());

class MemoryApp extends StatelessWidget {
  const MemoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memory Match',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamilyFallback: _C.fontFallback,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  // ── แก้ path โฟลเดอร์รูปตรงนี้ให้ตรงกับ pubspec.yaml ของคุณ ──────────────────
  static const _dir = 'assets/images/';

  static const images = [
    '${_dir}B.png',
    '${_dir}C.png',
    '${_dir}D.png',
    '${_dir}DP.png',
    '${_dir}H.png',
    '${_dir}HE.png',
    '${_dir}I.png',
    '${_dir}P.png',
    '${_dir}S.png',
    '${_dir}T.png',
  ];

  // ── รูปที่ใช้ในหน้าอื่นๆ (เปลี่ยนชื่อไฟล์ได้เลย) ─────────────────────────────
  static const readyImage = '${_dir}logo2.png'; // หน้า "Ready?" (แทนไอคอน 4 เหลี่ยม)
  static const pausedImage = '${_dir}logo2.png'; // หน้า "Paused"
  static const winImages = [
    '${_dir}CC.png',
  ]; // หน้า "All pairs found" (แสดงเรียงกัน; ใส่ 1-3 รูป)

  // สีพาสเทลหลังรูปแต่ละใบ ใช้เมื่อเลือก "Per character" (ลำดับตรงกับ images)
  static const tints = [
    Color(0xFFE8A9A9), // B  Black Widow
    Color(0xFFA5BDEB), // C  Captain America
    Color(0xFFF0BE9A), // D  Doctor Strange
    Color(0xFFE88F8F), // DP Deadpool
    Color(0xFF9ED3A8), // H  Hulk
    Color(0xFFC3B1E1), // HE Hawkeye
    Color(0xFFEBD58F), // I  Iron Man
    Color(0xFF9EA5B5), // P  Black Panther
    Color(0xFFF0B6CC), // S  Spider-Man
    Color(0xFF9ED3E6), // T  Thor
  ];

  static const mismatchDelay = Duration(milliseconds: 550);
  static const matchDelay = Duration(milliseconds: 380);
  static const popHold = Duration(milliseconds: 750);

  final _chime = ChimePlayer();
  final _watch = Stopwatch();
  Timer? _ticker;

  late List<MemCard> _cards;
  final List<int> _open = [];
  Phase _phase = Phase.idle;
  bool _locked = false;
  int _moves = 0;
  int _pairs = 0;
  int _round = 0;
  bool _precached = false;

  // ── ผู้เล่น + อันดับ ───────────────────────────────────────────────────────
  static const _storeKey = 'memory_match_avengers_scores';
  String _playerName = '';
  List<ScoreEntry> _scores = [];
  ScoreEntry? _lastEntry;
  int? _lastRank;
  bool _showScore = false; // หน้าสรุปคะแนนหลังจบเกมแสดงอยู่หรือยัง

  // ค่าเริ่มต้นของโทนสี (0 = Midnight) และพื้นหลังการ์ด (0 = White)
  int _themeIdx = 0;
  int _faceIdx = 0;

  GameTheme get _t => _themes[_themeIdx];

  Color _faceColor(int symbol) =>
      _faces[_faceIdx].color ??
      Color.alphaBlend(tints[symbol].withValues(alpha: 0.45), Colors.white);

  Color _faceBorder(int symbol) => _faces[_faceIdx].color == null
      ? tints[symbol].withValues(alpha: 0.7)
      : _t.line;

  @override
  void initState() {
    super.initState();
    _cards = _deal();
    _loadScores();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      for (final path in {...images, readyImage, pausedImage, ...winImages}) {
        precacheImage(AssetImage(path), context);
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _chime.stopMusic();
    super.dispose();
  }

  List<MemCard> _deal() {
    final list = [
      for (var i = 0; i < images.length; i++) ...[MemCard(i), MemCard(i)],
    ]..shuffle();
    return list;
  }

  // ── Controls ───────────────────────────────────────────────────────────────

  Future<void> _start() async {
    _chime.unlock();
    // กด Start (เริ่มใหม่) -> ถามชื่อก่อน / กด Resume -> เล่นต่อได้เลย
    if (_phase != Phase.paused) {
      final name = await _askName();
      if (name == null || !mounted) return;
      _playerName = name;
    }
    _beginPlay();
  }

  void _beginPlay() {
    setState(() {
      if (_phase == Phase.paused) {
        _watch.start();
      } else {
        _round++;
        _cards = _deal();
        _open.clear();
        _locked = false;
        _moves = 0;
        _pairs = 0;
        _lastEntry = null;
        _lastRank = null;
        _showScore = false;
        _watch
          ..reset()
          ..start();
      }
      _phase = Phase.playing;
    });
    _chime.startMusic();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _phase == Phase.playing) setState(() {});
    });
  }

  void _pause() {
    if (_phase != Phase.playing) return;
    _chime.stopMusic();
    setState(() {
      _watch.stop();
      _phase = Phase.paused;
    });
  }

  void _reset() {
    _ticker?.cancel();
    _chime.stopMusic();
    setState(() {
      _round++;
      _watch
        ..stop()
        ..reset();
      _cards = _deal();
      _open.clear();
      _locked = false;
      _moves = 0;
      _pairs = 0;
      _lastEntry = null;
      _lastRank = null;
      _showScore = false;
      _phase = Phase.idle;
    });
  }

  void _toggleMute() {
    setState(() => _chime.muted = !_chime.muted);
    if (_chime.muted) {
      _chime.stopMusic();
    } else if (_phase == Phase.playing) {
      _chime.startMusic();
    }
  }

  void _toggleMusic() {
    setState(() => _chime.musicOn = !_chime.musicOn);
    if (!_chime.musicOn) {
      _chime.stopMusic();
    } else if (_phase == Phase.playing) {
      _chime.startMusic();
    }
  }

  // ── Game logic ─────────────────────────────────────────────────────────────

  void _onTap(int i) {
    if (_phase != Phase.playing || _locked) return;
    final card = _cards[i];
    if (card.matched) return;

    // กดการ์ดที่เปิดค้างอยู่ใบเดียว -> พลิกกลับ (นับเป็น 1 move)
    if (card.faceUp) {
      if (_open.length == 1 && _open[0] == i) {
        setState(() {
          card.faceUp = false;
          _open.clear();
          _moves++;
        });
      }
      return;
    }

    // เปิดการ์ด (นับเป็น 1 move ทุกครั้งที่กดสำเร็จ)
    setState(() {
      card.faceUp = true;
      _open.add(i);
      _moves++;
    });
    if (_open.length < 2) return;

    _locked = true;
    final a = _cards[_open[0]];
    final b = _cards[_open[1]];
    final round = _round;

    if (a.symbol == b.symbol) {
      Future.delayed(matchDelay, () {
        if (!mounted || round != _round) return;
        _chime.match();
        setState(() {
          a.success = true;
          b.success = true;
          _pairs++;
          _open.clear();
          _locked = false;
          if (_pairs == images.length) _watch.stop();
        });

        Future.delayed(popHold, () {
          if (!mounted || round != _round) return;
          setState(() {
            a.matched = true;
            b.matched = true;
          });
          if (_cards.every((c) => c.matched)) _finish();
        });
      });
    } else {
      Future.delayed(mismatchDelay, () {
        if (!mounted || round != _round) return;
        setState(() {
          a.faceUp = false;
          b.faceUp = false;
          _open.clear();
          _locked = false;
        });
      });
    }
  }

  void _finish() {
    _watch.stop();
    _ticker?.cancel();
    _chime.stopMusic();

    final entry = ScoreEntry(
      _playerName.isEmpty ? 'Player' : _playerName,
      _moves,
      _watch.elapsedMilliseconds,
      DateTime.now().millisecondsSinceEpoch,
    );
    _scores.add(entry);
    _scores.sort(ScoreEntry.compare);
    if (_scores.length > 50) _scores.removeRange(50, _scores.length);
    _saveScores();
    final idx = _scores.indexOf(entry);

    setState(() {
      _lastEntry = entry;
      _lastRank = idx < 0 ? null : idx + 1;
      _phase = Phase.won;
    });

    // แสดงหน้าสรุปคะแนน + 5 อันดับแรก (ปุ่ม Play again / Reset รอจนกว่าหน้านี้จะขึ้น)
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _phase == Phase.won) setState(() => _showScore = true);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _phase == Phase.won) _chime.win();
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _time {
    final s = _watch.elapsed.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String get _status => switch (_phase) {
        Phase.idle => 'Press Start to begin',
        Phase.playing => '$_playerName · Find all ${images.length} pairs',
        Phase.paused => 'Paused',
        Phase.won => 'Board cleared',
      };

  String get _primaryLabel => switch (_phase) {
        Phase.paused => 'Resume',
        Phase.won => 'Play again',
        _ => 'Start',
      };

  // ── เก็บ/โหลดอันดับ (localStorage ของเบราว์เซอร์) ────────────────────────────

  void _loadScores() {
    try {
      final raw = _localStorage.getItem(_storeKey.toJS)?.toDart;
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _scores = [
        for (final j in list) ScoreEntry.fromJson(j as Map<String, dynamic>),
      ]..sort(ScoreEntry.compare);
    } catch (_) {}
  }

  void _saveScores() {
    try {
      _localStorage.setItem(
        _storeKey.toJS,
        jsonEncode([for (final e in _scores) e.toJson()]).toJS,
      );
    } catch (_) {}
  }

  // ── ถามชื่อผู้เล่นหลังกด Start ───────────────────────────────────────────────

  /// ชื่อนี้มีอยู่ในตารางอันดับแล้วหรือยัง (ไม่สนตัวพิมพ์เล็ก/ใหญ่)
  bool _nameTaken(String name) {
    final n = name.trim().toLowerCase();
    return _scores.any((e) => e.name.trim().toLowerCase() == n);
  }

  Future<String?> _askName() {
    final t = _t;
    // ถ้าชื่อเดิมถูกใช้ในตารางอันดับแล้ว ให้เริ่มด้วยช่องว่าง
    final ctrl = TextEditingController(
      text: _nameTaken(_playerName) ? '' : _playerName,
    );
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    String? error;

    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c),
        );

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          void submit() {
            final n = ctrl.text.trim();
            if (n.isEmpty) {
              setDlg(() => error = 'กรุณาใส่ชื่อผู้เล่น');
              return;
            }
            if (_nameTaken(n)) {
              setDlg(() => error = 'ชื่อนี้มีในตารางอันดับแล้ว กรุณาใช้ชื่ออื่น');
              return;
            }
            Navigator.pop(ctx, n);
          }

          return AlertDialog(
            backgroundColor: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: t.line),
            ),
            title: Text(
              'Player name',
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
            ),
            content: SizedBox(
              width: 320,
              child: TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 16,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                onChanged: (_) {
                  if (error != null) setDlg(() => error = null);
                },
                cursorColor: t.accent,
                style: TextStyle(color: t.text, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  hintStyle: TextStyle(color: t.textDim),
                  counterStyle: TextStyle(color: t.textDim),
                  errorText: error,
                  errorStyle: const TextStyle(color: Colors.redAccent),
                  enabledBorder: border(t.line),
                  focusedBorder: border(t.accent),
                  errorBorder: border(Colors.redAccent),
                  focusedErrorBorder: border(Colors.redAccent),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: t.textDim)),
              ),
              TextButton(
                onPressed: submit,
                child: Text(
                  'Start',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── ตารางอันดับ ────────────────────────────────────────────────────────────

  // คอลัมน์ตารางอันดับ: อันดับ | ผู้เล่น | เปิดไพ่ | เวลา
  static const _colRank = 48.0;
  static const _colFlips = 78.0;
  static const _colTime = 84.0;

  Widget _scoreHeader(GameTheme t) {
    final h = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: t.text,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          SizedBox(
            width: _colRank,
            child: Text('อันดับ', textAlign: TextAlign.right, style: h),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('ผู้เล่น', style: h)),
          SizedBox(
            width: _colFlips,
            child: Text('เปิดไพ่', textAlign: TextAlign.right, style: h),
          ),
          SizedBox(
            width: _colTime,
            child: Text('เวลา', textAlign: TextAlign.right, style: h),
          ),
        ],
      ),
    );
  }

  Widget _scoreRow(int rank, ScoreEntry e, GameTheme t, bool highlight) {
    final ts = TextStyle(
      fontSize: 14,
      color: t.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? t.accent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? t.accent : t.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _colRank,
            child: Text('$rank', textAlign: TextAlign.right, style: ts),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts,
            ),
          ),
          SizedBox(
            width: _colFlips,
            child: Text('${e.moves} ครั้ง',
                textAlign: TextAlign.right, style: ts),
          ),
          SizedBox(
            width: _colTime,
            child: Text(_fmtSec(e.ms), textAlign: TextAlign.right, style: ts),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext sheetCtx) async {
    final t = _t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.line),
        ),
        title: Text('Clear leaderboard?', style: TextStyle(color: t.text)),
        content: Text('All saved scores will be deleted.',
            style: TextStyle(color: t.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: t.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear',
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _scores.clear();
      _lastEntry = null;
      _lastRank = null;
    });
    _saveScores();
    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
  }

  /// ตาราง 5 อันดับแรก (ใช้ทั้งในหน้าสรุปคะแนนและหน้าถ้วยรางวัล)
  Widget _scoreTable(GameTheme t) {
    final top = _scores.take(5).toList();
    if (top.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'ยังไม่มีคะแนน เล่นให้จบเพื่อขึ้นอันดับ',
            style: TextStyle(fontSize: 14, color: t.textDim),
          ),
        ),
      );
    }
    final last = _lastEntry;
    final rank = _lastRank;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _scoreHeader(t),
        for (var i = 0; i < top.length; i++)
          _scoreRow(i + 1, top[i], t, identical(top[i], last)),
        // ถ้ารอบนี้อยู่นอก 5 อันดับ ให้โชว์แถวของรอบนี้ต่อท้าย
        if (last != null && rank != null && rank > top.length) ...[
          Text('···', style: TextStyle(color: t.textDim)),
          const SizedBox(height: 4),
          _scoreRow(rank, last, t, true),
        ],
      ],
    );
  }

  void _openLeaderboard() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) {
        final t = _t;
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.line),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'LEADERBOARD · TOP 5',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: t.textDim,
                        ),
                      ),
                    ),
                    if (_scores.isNotEmpty)
                      TextButton(
                        onPressed: () => _confirmClear(ctx),
                        child:
                            Text('Clear', style: TextStyle(color: t.textDim)),
                      ),
                  ],
                ),
                Text(
                  'เปิดไพ่น้อยครั้งที่สุดชนะ ถ้าเท่ากันดูที่เวลา',
                  style: TextStyle(fontSize: 13, color: t.textDim),
                ),
                const SizedBox(height: 12),
                _scoreTable(t),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Settings sheet (เลือกโทนสี + พื้นหลังการ์ด) ─────────────────────────────

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final t = _t;
          void pick(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          TextStyle label() => TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: t.textDim,
              );

          return Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: t.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THEME', style: label()),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _themes.length; i++)
                      _OptionChip(
                        label: _themes[i].name,
                        dot: _themes[i].bgTop,
                        selected: i == _themeIdx,
                        t: t,
                        onTap: () => pick(() => _themeIdx = i),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('CARD BACKGROUND', style: label()),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _faces.length; i++)
                      _OptionChip(
                        label: _faces[i].name,
                        dot: _faces[i].color,
                        selected: i == _faceIdx,
                        t: t,
                        onTap: () => pick(() => _faceIdx = i),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 720;
    final t = _t;

    return Scaffold(
      backgroundColor: t.bgBottom,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [t.bgTop, t.bgBottom],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Column(
                        children: [
                          _header(),
                          const SizedBox(height: 2),
                          _clock(compact),
                          SizedBox(height: compact ? 10 : 18),
                          Expanded(child: _board()),
                          SizedBox(height: compact ? 14 : 20),
                          _controls(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_phase == Phase.won) const Positioned.fill(child: _Fireworks()),
        ],
      ),
    );
  }

  Widget _header() {
    final t = _t;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Memory Match',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                  color: t.text,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Leaderboard',
          onPressed: _openLeaderboard,
          icon: Icon(Icons.emoji_events_outlined, color: t.textDim),
        ),
        IconButton(
          tooltip: 'Theme & card background',
          onPressed: _openSettings,
          icon: Icon(Icons.palette_outlined, color: t.textDim),
        ),
        IconButton(
          tooltip: _chime.musicOn ? 'Turn music off' : 'Turn music on',
          onPressed: _toggleMusic,
          icon: Icon(
            _chime.musicOn ? Icons.music_note_rounded : Icons.music_off_rounded,
            color: t.textDim,
          ),
        ),
        IconButton(
          tooltip: _chime.muted ? 'Turn sound on' : 'Turn sound off',
          onPressed: _toggleMute,
          icon: Icon(
            _chime.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: t.textDim,
          ),
        ),
      ],
    );
  }

  Widget _clock(bool compact) {
    final t = _t;
    return Column(
      children: [
        Text(
          _time,
          style: TextStyle(
            fontSize: compact ? 44 : 60,
            fontWeight: FontWeight.w200,
            letterSpacing: -1,
            height: 1.1,
            color: t.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            _status,
            key: ValueKey(_status),
            style: TextStyle(fontSize: 15, color: t.textDim),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stat('Pairs', '$_pairs/${images.length}'),
            const SizedBox(width: 28),
            _stat('Moves', '$_moves'),
          ],
        ),
      ],
    );
  }

  Widget _stat(String label, String value) {
    final t = _t;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: t.textDim)),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: t.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _board() {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      final total = _cards.length;

      final cols = w >= 760 ? 7 : (w >= 480 ? 5 : 4);
      final rows = (total / cols).ceil();
      const gap = 12.0;
      const ratio = 1.12;

      final byW = (w - gap * (cols - 1)) / cols;
      final byH = ((h - gap * (rows - 1)) / rows) / ratio;
      final cw = math.max(36.0, math.min(math.min(byW, byH), 150.0));
      final ch = cw * ratio;
      final gridW = cols * cw + (cols - 1) * gap + 1;

      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: gridW,
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < total; i++)
                  _FlipCard(
                    card: _cards[i],
                    t: _t,
                    faceColor: _faceColor(_cards[i].symbol),
                    faceBorder: _faceBorder(_cards[i].symbol),
                    image: images[_cards[i].symbol],
                    width: cw,
                    height: ch,
                    onTap: () => _onTap(i),
                  ),
              ],
            ),
          ),
          _coverOverlay(),
          _resultCard(math.min(w, 480.0), h),
        ],
      );
    });
  }

  /// ฝ้าเบลอก่อนกด Start (บางๆ มองเห็นการ์ดด้านหลังได้นิดหน่อย)
  /// ตอน Pause จะเบลอหนักและทึบกว่า เพื่อไม่ให้แอบดูการ์ดที่เปิดค้างไว้
  Widget _coverOverlay() {
    final t = _t;
    final show = _phase == Phase.idle || _phase == Phase.paused;
    final idle = _phase == Phase.idle;

    final sigma = idle ? 5.0 : 18.0; // ยิ่งมากยิ่งเบลอ
    final tintAlpha = idle ? 0.30 : 0.78; // ยิ่งน้อยยิ่งโปร่งใส

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: Container(
                color: t.bgTop.withValues(alpha: tintAlpha),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // รูปแทนไอคอน 4 เหลี่ยม / ไอคอน pause
                    _asset(idle ? readyImage : pausedImage, 96, t.backMark),
                    const SizedBox(height: 12),
                    Text(
                      idle ? 'Ready?' : 'Paused',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      idle
                          ? 'Match all ${images.length} pairs as fast as you can'
                          : 'Cards are hidden until you resume',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: t.textDim),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: 170,
                      child: _PillButton(
                        t: t,
                        label: idle ? 'Start' : 'Resume',
                        icon: Icons.play_arrow_rounded,
                        primary: true,
                        onPressed: show ? _start : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// หน้าสรุปคะแนนหลังจบเกม (ธีมเดียวกับเกม) แสดงก่อนเริ่มใหม่/รีเซ็ต
  Widget _resultCard(double w, double h) {
    final t = _t;
    final show = _phase == Phase.won && _showScore;
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: show ? 1 : 0.92,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          child: Container(
            width: w,
            constraints: BoxConstraints(maxHeight: h),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: t.line),
              boxShadow: [
                BoxShadow(
                  color: t.shadow.withValues(alpha: t.dark ? 0.5 : 0.16),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in winImages)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _asset(p, 64, t.textDim),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'All pairs found',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _playerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'เปิดไพ่ $_moves ครั้ง · เวลา ${_fmtSec(_watch.elapsedMilliseconds)}',
                    style: TextStyle(fontSize: 15, color: t.textDim),
                  ),
                  if (_lastRank != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'อันดับ $_lastRank',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: t.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'TOP 5',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: t.textDim,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _scoreTable(t),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 170,
                    child: _PillButton(
                      t: t,
                      label: 'Play again',
                      icon: Icons.play_arrow_rounded,
                      primary: true,
                      onPressed: show ? _start : null,
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

  Widget _controls() {
    final t = _t;
    final scoreWait = _phase == Phase.won && !_showScore;
    final canStart = _phase != Phase.playing && !scoreWait;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _PillButton(
              t: t,
              label: _primaryLabel,
              icon: Icons.play_arrow_rounded,
              primary: true,
              onPressed: canStart ? _start : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: _PillButton(
              t: t,
              label: 'Pause',
              icon: Icons.pause_rounded,
              onPressed: _phase == Phase.playing ? _pause : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: _PillButton(
              t: t,
              label: 'Reset',
              icon: Icons.refresh_rounded,
              onPressed: (_phase == Phase.idle || scoreWait) ? null : _reset,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.t,
    this.dot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final GameTheme t;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? t.accent : t.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot,
                  border: Border.all(color: t.line),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? t.onAccent : t.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({
    required this.card,
    required this.t,
    required this.faceColor,
    required this.faceBorder,
    required this.image,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final MemCard card;
  final GameTheme t;
  final Color faceColor; // พื้นหลังภายในการ์ด (ด้านรูป)
  final Color faceBorder;
  final String image;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final faceUp = card.faceUp || card.success || card.matched;

    final double scale = card.matched ? 0.8 : (card.success ? 1.14 : 1.0);
    final scaleDuration = Duration(milliseconds: card.matched ? 450 : 650);
    final scaleCurve = card.matched
        ? Curves.easeInCubic
        : (card.success ? Curves.elasticOut : Curves.easeOut);

    return IgnorePointer(
      ignoring: card.matched,
      child: AnimatedOpacity(
        opacity: card.matched ? 0 : 1,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: scale,
          duration: scaleDuration,
          curve: scaleCurve,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: width,
              height: height,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: faceUp ? math.pi : 0),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeInOutCubic,
                builder: (context, angle, _) {
                  final showFront = angle > math.pi / 2;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angle),
                    child: showFront
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(math.pi),
                            child: _front(),
                          )
                        : _back(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<BoxShadow> get _shadow => [
        BoxShadow(
          color: t.shadow.withValues(alpha: t.dark ? 0.45 : 0.14),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ];

  Widget _back() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_C.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.backA, t.backB],
        ),
        border: Border.all(color: t.line),
        boxShadow: _shadow,
      ),
      alignment: Alignment.center,
      child: Container(
        width: width * 0.22,
        height: width * 0.22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.backMark.withValues(alpha: 0.7), width: 2),
        ),
      ),
    );
  }

  Widget _front() {
    final ok = card.success;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      padding: EdgeInsets.all(width * 0.08),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_C.radius),
        color: ok ? _C.matchFill : faceColor,
        border: Border.all(
          color: ok ? _C.matchLine : faceBorder,
          width: ok ? 2 : 1,
        ),
        boxShadow: ok
            ? [
                BoxShadow(
                  color: _C.matchLine.withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ]
            : _shadow,
      ),
      alignment: Alignment.center,
      child: Image.asset(
        image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Icon(
          Icons.broken_image_outlined,
          size: width * 0.4,
          color: t.textDim,
        ),
      ),
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.t,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final GameTheme t;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final enabled = widget.onPressed != null;

    // ── สีปุ่ม: ปุ่มหลัก (Start/Resume) = t.accent, ปุ่มรอง (Pause/Reset) = t.surface
    final bg = widget.primary ? t.accent : t.surface;
    final fg = widget.primary ? t.onAccent : t.text;

    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.4,
      duration: const Duration(milliseconds: 220),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 52,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(_C.radius),
              border: widget.primary ? null : Border.all(color: t.line),
              boxShadow: [
                BoxShadow(
                  color: t.shadow.withValues(alpha: t.dark ? 0.45 : 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 20, color: fg),
                const SizedBox(width: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    widget.label,
                    key: ValueKey(widget.label),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fireworks (plays once when the board is cleared)
// ─────────────────────────────────────────────────────────────────────────────

class _Particle {
  const _Particle(this.angle, this.speed, this.size);
  final double angle;
  final double speed;
  final double size;
}

class _Burst {
  const _Burst(this.origin, this.start, this.color, this.particles);
  final Offset origin;
  final double start;
  final Color color;
  final List<_Particle> particles;
}

class _Fireworks extends StatefulWidget {
  const _Fireworks();

  @override
  State<_Fireworks> createState() => _FireworksState();
}

class _FireworksState extends State<_Fireworks>
    with SingleTickerProviderStateMixin {
  static const _total = 4.4;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_total * 1000).round()),
  )..forward();

  late final List<_Burst> _bursts = _makeBursts();

  List<_Burst> _makeBursts() {
    final r = math.Random();
    const colors = [
      Color(0xFFF2B84B),
      Color(0xFFEE7F96),
      Color(0xFF6CC4A1),
      Color(0xFF6FA8E8),
      Color(0xFFA58BEA),
      Color(0xFFF59B6B),
    ];
    return List.generate(8, (i) {
      return _Burst(
        Offset(0.14 + 0.72 * r.nextDouble(), 0.12 + 0.36 * r.nextDouble()),
        i * 0.42 + r.nextDouble() * 0.15,
        colors[i % colors.length],
        List.generate(
          48,
          (_) => _Particle(
            r.nextDouble() * 2 * math.pi,
            110 + r.nextDouble() * 140,
            1.6 + r.nextDouble() * 1.8,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(painter: _FireworksPainter(_bursts, _c, _total)),
      ),
    );
  }
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.bursts, this.controller, this.total)
      : super(repaint: controller);

  final List<_Burst> bursts;
  final AnimationController controller;
  final double total;

  static const _life = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final time = controller.value * total;
    final scale = (math.min(size.width, size.height) / 600).clamp(0.6, 1.5);

    for (final b in bursts) {
      final t = time - b.start;
      if (t < 0 || t > _life) continue;

      final fade = math.pow(1 - t / _life, 1.6).toDouble();
      final origin = Offset(b.origin.dx * size.width, b.origin.dy * size.height);

      if (t < 0.18) {
        canvas.drawCircle(
          origin,
          26 * scale * (1 - t / 0.18),
          Paint()..color = b.color.withValues(alpha: 0.35 * (1 - t / 0.18)),
        );
      }

      Offset pos(_Particle p, double tt) {
        final d = p.speed * scale * (1 - math.exp(-2.4 * tt)) / 1.0;
        final g = 70 * scale * tt * tt;
        return origin + Offset(math.cos(p.angle) * d, math.sin(p.angle) * d + g);
      }

      final line = Paint()
        ..color = b.color.withValues(alpha: fade)
        ..strokeCap = StrokeCap.round;
      final dot = Paint()..color = b.color.withValues(alpha: fade);

      for (final p in b.particles) {
        final now = pos(p, t);
        final before = pos(p, math.max(0, t - 0.07));
        line.strokeWidth = p.size * scale;
        canvas.drawLine(before, now, line);
        canvas.drawCircle(now, p.size * 0.8 * scale, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter old) => false;
}
