import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/fnv_hash.dart';
import 'package:vietyaku/features/dictionary/data/binary_cache.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_loader.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';

void main() {
  final sample = <String, String>{
    '覚悟': 'giác ngộ/quyết tâm',
    '持ち歩': 'mang theo',
    'キー': 'value có = và /slash',
    '一': '',
  };

  group('BinaryCache', () {
    test('encode/decode round-trip preserves all entries', () {
      final bytes = BinaryCache.encode(sample,
          srcHash: 0x1234, srcSize: 100, srcMtimeMs: 999);
      final decoded = BinaryCache.decode(bytes);
      expect(decoded, sample);
    });

    test('header round-trip', () {
      final bytes = BinaryCache.encode(sample,
          srcHash: -42, srcSize: 5270000, srcMtimeMs: 1720000000000);
      final header = BinaryCache.readHeader(bytes)!;
      expect(header.srcHash, -42);
      expect(header.srcSize, 5270000);
      expect(header.srcMtimeMs, 1720000000000);
      expect(header.count, sample.length);
    });

    test('rejects garbage and truncated bytes', () {
      expect(BinaryCache.decode(Uint8List.fromList([1, 2, 3])), isNull);
      final bytes = BinaryCache.encode(sample,
          srcHash: 1, srcSize: 1, srcMtimeMs: 1);
      expect(BinaryCache.decode(bytes.sublist(0, bytes.length - 3)), isNull);
    });

    test('isValid: same size+mtime → valid without hashing', () {
      final bytes = BinaryCache.encode(sample,
          srcHash: 0xAB, srcSize: 100, srcMtimeMs: 50);
      var hashed = false;
      final valid = BinaryCache.isValid(bytes,
          srcSize: 100,
          srcMtimeMs: 50,
          readSrcBytes: () {
            hashed = true;
            return Uint8List(0);
          });
      expect(valid, isTrue);
      expect(hashed, isFalse);
    });

    test('isValid: size changed → invalid', () {
      final bytes = BinaryCache.encode(sample,
          srcHash: 0xAB, srcSize: 100, srcMtimeMs: 50);
      expect(
        BinaryCache.isValid(bytes,
            srcSize: 101, srcMtimeMs: 50, readSrcBytes: () => Uint8List(0)),
        isFalse,
      );
    });

    test('isValid: mtime changed, content identical → valid via FNV-1a', () {
      final srcBytes = Uint8List.fromList(utf8.encode('一=nhất\n'));
      final bytes = BinaryCache.encode(sample,
          srcHash: fnv1a64(srcBytes),
          srcSize: srcBytes.length,
          srcMtimeMs: 50);
      expect(
        BinaryCache.isValid(bytes,
            srcSize: srcBytes.length,
            srcMtimeMs: 99999, // Google Drive sync đổi mtime
            readSrcBytes: () => srcBytes),
        isTrue,
      );
    });

    test('isValid: mtime changed and content changed → invalid', () {
      final oldBytes = Uint8List.fromList(utf8.encode('一=nhất\n'));
      final newBytes = Uint8List.fromList(utf8.encode('一=mới!\n'));
      final bytes = BinaryCache.encode(sample,
          srcHash: fnv1a64(oldBytes),
          srcSize: oldBytes.length,
          srcMtimeMs: 50);
      expect(
        BinaryCache.isValid(bytes,
            srcSize: newBytes.length,
            srcMtimeMs: 99999,
            readSrcBytes: () => newBytes),
        isFalse,
      );
    });
  });

  group('loadDictionarySync with temp files', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('vydc_test');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('cold load parses text and writes cache; warm load hits cache', () {
      final src = File('${temp.path}\\dict.txt')
        ..writeAsStringSync('﻿覚悟=giác ngộ\n持ち歩=mang theo\n');
      final cachePath = '${temp.path}\\dict.vydc';

      final cold = loadDictionarySync(
          sourcePath: src.path,
          cachePath: cachePath,
          type: DictType.vietPhrase);
      expect(cold.fromCache, isFalse);
      expect(cold.dictionary.entries['覚悟'], 'giác ngộ');
      expect(File(cachePath).existsSync(), isTrue);

      final warm = loadDictionarySync(
          sourcePath: src.path,
          cachePath: cachePath,
          type: DictType.vietPhrase);
      expect(warm.fromCache, isTrue);
      expect(warm.dictionary.entries, cold.dictionary.entries);
    });

    test('source content change invalidates cache', () {
      final src = File('${temp.path}\\dict.txt')..writeAsStringSync('一=nhất\n');
      final cachePath = '${temp.path}\\dict.vydc';
      loadDictionarySync(
          sourcePath: src.path,
          cachePath: cachePath,
          type: DictType.vietPhrase);

      src.writeAsStringSync('一=nhất\n二=nhị\n');
      final reload = loadDictionarySync(
          sourcePath: src.path,
          cachePath: cachePath,
          type: DictType.vietPhrase);
      expect(reload.fromCache, isFalse);
      expect(reload.dictionary.entries.length, 2);
    });

    test('mtime-only change (same bytes) still uses cache', () {
      final src = File('${temp.path}\\dict.txt')..writeAsStringSync('一=nhất\n');
      final cachePath = '${temp.path}\\dict.vydc';
      loadDictionarySync(
          sourcePath: src.path,
          cachePath: cachePath,
          type: DictType.vietPhrase);

      src.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
      final reload = loadDictionarySync(
          sourcePath: src.path,
          cachePath: cachePath,
          type: DictType.vietPhrase);
      expect(reload.fromCache, isTrue);
    });

    test('missing source file → empty dictionary', () {
      final result = loadDictionarySync(
          sourcePath: '${temp.path}\\missing.txt',
          cachePath: '${temp.path}\\missing.vydc',
          type: DictType.userDict);
      expect(result.dictionary.isEmpty, isTrue);
    });
  });
}
