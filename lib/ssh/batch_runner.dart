import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'connector.dart';

class BatchResult {
  BatchResult(this.host);

  final Host host;
  bool running = true;
  int? exitCode;
  String output = '';
  String? error;

  bool get ok => !running && error == null && (exitCode ?? 0) == 0;
}

/// Runs one command on many hosts in parallel (bounded concurrency).
class BatchRunner extends ChangeNotifier {
  BatchRunner(this.connector, this.hosts, this.command, {this.concurrency = 6})
      : results = [for (final h in hosts) BatchResult(h)];

  final SshConnector connector;
  final List<Host> hosts;
  final String command;
  final int concurrency;
  final List<BatchResult> results;

  bool get finished => results.every((r) => !r.running);

  Future<void> run() async {
    var next = 0;
    Future<void> worker() async {
      while (next < results.length) {
        final r = results[next++];
        await _runOne(r);
      }
    }

    await Future.wait(
        List.generate(concurrency.clamp(1, results.length), (_) => worker()));
  }

  Future<void> _runOne(BatchResult r) async {
    SshConnection? conn;
    try {
      conn = await connector.connect(r.host);
      final res = await conn.client
          .runWithResult(command)
          .timeout(const Duration(minutes: 10));
      r
        ..exitCode = res.exitCode
        ..output = utf8.decode(res.output, allowMalformed: true);
    } catch (e) {
      r.error = '$e';
    } finally {
      conn?.close();
      r.running = false;
      notifyListeners();
    }
  }
}
