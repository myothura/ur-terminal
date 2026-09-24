import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Per-device UI preferences (not secret, not synced).
class Prefs {
  Prefs._();

  static final Prefs I = Prefs._();

  final ValueNotifier<double> fontSize = ValueNotifier(13.5);

  /// Terminal background opacity over the window blur. 1.0 = solid.
  final ValueNotifier<double> terminalOpacity = ValueNotifier(0.82);

  File? _file;
  Timer? _save;

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _file = File('${dir.path}/prefs.json');
    try {
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        fontSize.value = (j['fontSize'] as num?)?.toDouble() ?? fontSize.value;
        terminalOpacity.value =
            (j['terminalOpacity'] as num?)?.toDouble() ?? terminalOpacity.value;
      }
    } catch (e) {
      debugPrint('prefs: $e');
    }
    fontSize.addListener(_scheduleSave);
    terminalOpacity.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), () {
      _file?.writeAsString(jsonEncode({
        'fontSize': fontSize.value,
        'terminalOpacity': terminalOpacity.value,
      }));
    });
  }
}
