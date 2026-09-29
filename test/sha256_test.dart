import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forna_dagar_launcher/services/sha256.dart';

void main() {
  // Vettori di prova ufficiali (FIPS 180-4 / NIST).
  test('stringa vuota', () {
    expect(sha256Hex(const []), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('"abc"', () {
    expect(sha256Hex(utf8.encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('messaggio lungo 56 byte (il padding richiede un secondo blocco)', () {
    expect(
      sha256Hex(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  test('frase nota', () {
    expect(
      sha256Hex(utf8.encode('The quick brown fox jumps over the lazy dog')),
      'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
    );
  });

  test('un milione di "a"', () {
    expect(
      sha256Hex(List.filled(1000000, 0x61)),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });

  test('aggiungere i dati a pezzi da lo stesso risultato', () {
    final data = List.generate(1000, (i) => i % 251);
    final whole = sha256Hex(data);
    final pieces = Sha256()
      ..add(data.sublist(0, 1))
      ..add(data.sublist(1, 65))
      ..add(data.sublist(65, 700))
      ..add(data.sublist(700));
    expect(pieces.close(), whole);
  });

  test('sha256OfFile legge il file a blocchi', () async {
    final dir = Directory.systemTemp.createTempSync('sha_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}dati.bin')..writeAsBytesSync(List.filled(200000, 0x61));
    expect(await sha256OfFile(file), sha256Hex(List.filled(200000, 0x61)));
  });
}
