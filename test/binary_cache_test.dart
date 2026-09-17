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
      final bytes = BinaryCache.encode(
        sample,
        srcHash: 0x1234,
        srcSize: 100,
        srcMtimeMs: 999,
      );
      final decoded = BinaryCache.decode(bytes);
      expect(decoded, sample);
    });

    test('header round-trip', () {
      final bytes = BinaryCache.encode(
        sample,
        srcHash: -42,
        srcSize: 5270000,
        srcMtimeMs: 1720000000000,
      );
      final header = BinaryCache.readHeader(bytes)!;
      expect(header.srcHash, -42);
      expect(header.srcSize, 5270000);
      expect(header.srcMtimeMs, 1720000000000);
      expect(header.count, sample.length);
    });

    test('rejects garbage and truncated bytes', () {
      expect(BinaryCache.decode(Uint8List.fromList([1, 2, 3])), isNull);
      final bytes = BinaryCache.encode(
        sample,
        srcHash: 1,
        srcSize: 1,
        srcMtimeMs: 1,
      );
      expect(BinaryCache.decode(bytes.sublist(0, bytes.length - 3)), isNull);
    });

    test('isValid: same size+mtime → valid without hashing', () {
      final bytes = BinaryCache.encode(
        sample,
        srcHash: 0xAB,
        srcSize: 100,
        srcMtimeMs: 50,
      );
      var hashed = false;
      final valid = BinaryCache.isValid(
        bytes,
        srcSize: 100,
        srcMtimeMs: 50,
        cacheMtimeMs: 50 + BinaryCache.mtimeSlackMs,
        readSrcBytes: () {
          hashed = true;
          return Uint8List(0);
        },
      );
      expect(valid, isTrue);
      expect(hashed, isFalse);
    });

    test('isValid: size changed → invalid', () {
      final bytes = BinaryCache.encode(
        sample,
        srcHash: 0xAB,
        srcSize: 100,
        srcMtimeMs: 50,
      );
      expect(
        BinaryCache.isValid(
          bytes,
          srcSize: 101,
          srcMtimeMs: 50,
          cacheMtimeMs: 50 + BinaryCache.mtimeSlackMs,
          readSrcBytes: () => Uint8List(0),
        ),
        isFalse,
      );
    });

    test('isValid: mtime changed, content identical → valid via FNV-1a', () {
      final srcBytes = Uint8List.fromList(utf8.encode('一=nhất\n'));
      final bytes = BinaryCache.encode(
        sample,
        srcHash: fnv1a64(srcBytes),
        srcSize: srcBytes.length,
        srcMtimeMs: 50,
      );
      expect(
        BinaryCache.isValid(
          bytes,
          srcSize: srcBytes.length,
          srcMtimeMs: 99999, // Google Drive sync đổi mtime
          cacheMtimeMs: 50 + BinaryCache.mtimeSlackMs,
          readSrcBytes: () => srcBytes,
        ),
        isTrue,
      );
    });

    test('isValid: mtime changed and content changed → invalid', () {
      final oldBytes = Uint8List.fromList(utf8.encode('一=nhất\n'));
      final newBytes = Uint8List.fromList(utf8.encode('一=mới!\n'));
      final bytes = BinaryCache.encode(
        sample,
        srcHash: fnv1a64(oldBytes),
        srcSize: oldBytes.length,
        srcMtimeMs: 50,
      );
      expect(
        BinaryCache.isValid(
          bytes,
          srcSize: newBytes.length,
          srcMtimeMs: 99999,
          cacheMtimeMs: 50 + BinaryCache.mtimeSlackMs,
          readSrcBytes: () => newBytes,
        ),
        isFalse,
      );
    });
  });

  test('isValid: mtime trùng nhưng nguồn ghi cùng lúc cache → phải hash', () {
    final oldBytes = Uint8List.fromList(utf8.encode('一=xử lý\n'));
    final newBytes = Uint8List.fromList(utf8.encode('一=xử lí\n'));
    final bytes = BinaryCache.encode(
      const {'一': 'xử lý'},
      srcHash: fnv1a64(oldBytes),
      srcSize: oldBytes.length,
      srcMtimeMs: 5000,
    );
    expect(
      BinaryCache.isValid(
        bytes,
        srcSize: newBytes.length,
        srcMtimeMs: 5000,
        cacheMtimeMs: 5000,
        readSrcBytes: () => newBytes,
      ),
      isFalse,
    );
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
        type: DictType.vietPhrase,
      );
      expect(cold.fromCache, isFalse);
      expect(cold.dictionary.entries['覚悟'], 'giác ngộ');
      expect(File(cachePath).existsSync(), isTrue);

      final warm = loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );
      expect(warm.fromCache, isTrue);
      expect(warm.dictionary.entries, cold.dictionary.entries);
    });

    test('source content change invalidates cache', () {
      final src = File('${temp.path}\\dict.txt')..writeAsStringSync('一=nhất\n');
      final cachePath = '${temp.path}\\dict.vydc';
      loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );

      src.writeAsStringSync('一=nhất\n二=nhị\n');
      final reload = loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );
      expect(reload.fromCache, isFalse);
      expect(reload.dictionary.entries.length, 2);
    });

    test('mtime-only change (same bytes) still uses cache', () {
      final src = File('${temp.path}\\dict.txt')..writeAsStringSync('一=nhất\n');
      final cachePath = '${temp.path}\\dict.vydc';
      loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );

      src.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
      final reload = loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );
      expect(reload.fromCache, isTrue);
    });

    test('ghi lại cùng kích thước, cùng mtime (mtime làm tròn giây) → không '
        'dùng cache cũ', () {
      final src = File('${temp.path}\\dict.txt')..writeAsStringSync('一=xử lý\n');
      final cachePath = '${temp.path}\\dict.vydc';
      loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );
      final mtime = src.lastModifiedSync();

      // Windows trả mtime theo giây: lần ghi thứ hai trong cùng giây giữ y mtime.
      src.writeAsStringSync('一=xử lí\n');
      src.setLastModifiedSync(mtime);
      final reload = loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );
      expect(reload.dictionary.entries['一'], 'xử lí');
    });

    test('nguồn đã cũ khi ghi cache → lần sau tin mtime, không hash', () {
      final src = File('${temp.path}\\dict.txt')..writeAsStringSync('一=nhất\n');
      src.setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      final cachePath = '${temp.path}\\dict.vydc';
      loadDictionarySync(
        sourcePath: src.path,
        cachePath: cachePath,
        type: DictType.vietPhrase,
      );
      final cacheBytes = File(cachePath).readAsBytesSync();
      final stat = src.statSync();

      var hashed = false;
      expect(
        BinaryCache.isValid(
          cacheBytes,
          srcSize: stat.size,
          srcMtimeMs: stat.modified.millisecondsSinceEpoch,
          cacheMtimeMs: File(
            cachePath,
          ).lastModifiedSync().millisecondsSinceEpoch,
          readSrcBytes: () {
            hashed = true;
            return src.readAsBytesSync();
          },
        ),
        isTrue,
      );
      expect(hashed, isFalse);
    });

    test('missing source file → empty dictionary', () {
      final result = loadDictionarySync(
        sourcePath: '${temp.path}\\missing.txt',
        cachePath: '${temp.path}\\missing.vydc',
        type: DictType.userDict,
      );
      expect(result.dictionary.isEmpty, isTrue);
    });
  });
}
