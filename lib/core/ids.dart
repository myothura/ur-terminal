import 'dart:math';

final Random _rng = Random.secure();

/// Random UUID v4 string.
String newId() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

List<int> randomBytes(int length) =>
    List<int>.generate(length, (_) => _rng.nextInt(256));

/// Hybrid logical clock.
///
/// Stamps are fixed-width strings `<millis:13>-<counter:4>-<node>` so that a
/// plain string comparison gives the causal order used for per-record
/// last-write-wins merging during sync.
class Hlc {
  Hlc(this.node);

  final String node;
  int _lastMillis = 0;
  int _counter = 0;

  String now() {
    final wall = DateTime.now().millisecondsSinceEpoch;
    if (wall > _lastMillis) {
      _lastMillis = wall;
      _counter = 0;
    } else {
      _counter++;
    }
    return _format(_lastMillis, _counter);
  }

  /// Advance the clock past a stamp received from another device.
  void observe(String stamp) {
    final parts = stamp.split('-');
    if (parts.length < 2) return;
    final millis = int.tryParse(parts[0]) ?? 0;
    final counter = int.tryParse(parts[1]) ?? 0;
    if (millis > _lastMillis ||
        (millis == _lastMillis && counter > _counter)) {
      _lastMillis = millis;
      _counter = counter;
    }
  }

  String _format(int millis, int counter) =>
      '${millis.toString().padLeft(13, '0')}-'
      '${counter.toString().padLeft(4, '0')}-$node';
}
