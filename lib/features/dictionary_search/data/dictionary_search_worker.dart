import 'dart:async';
import 'dart:isolate';

import '../domain/dictionary_search.dart';

class DictionarySearchWorker {
  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<DictionarySearchResponse>> _pending = {};
  late final StreamSubscription<Object?> _subscription;
  var _nextId = 0;

  DictionarySearchWorker._(this._isolate, this._commands, this._responses) {
    _subscription = _responses.listen(_handleResponse);
  }

  static Future<DictionarySearchWorker> start(
    List<DictionarySearchLayer> layers,
  ) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, (ready.sendPort, layers));
    final commands = await ready.first as SendPort;
    ready.close();
    final responses = ReceivePort();
    return DictionarySearchWorker._(isolate, commands, responses);
  }

  Future<DictionarySearchResponse> search(DictionarySearchQuery query) {
    final id = _nextId++;
    final completer = Completer<DictionarySearchResponse>();
    _pending[id] = completer;
    _commands.send((id, query, _responses.sendPort));
    return completer.future;
  }

  void _handleResponse(Object? message) {
    final response = message as (int, DictionarySearchResponse);
    _pending.remove(response.$1)?.complete(response.$2);
  }

  void close() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Search worker đã đóng'));
      }
    }
    _pending.clear();
    _subscription.cancel();
    _isolate.kill(priority: Isolate.immediate);
    _responses.close();
  }
}

void _workerMain((SendPort, List<DictionarySearchLayer>) startup) {
  final (ready, layers) = startup;
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.listen((message) {
    final (id, query, replyTo) =
        message as (int, DictionarySearchQuery, SendPort);
    replyTo.send((id, searchDictionaryLayers(layers, query)));
  });
}
