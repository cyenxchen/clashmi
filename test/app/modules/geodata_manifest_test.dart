import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled geodata manifest matches asset files', () async {
    final manifestFile = File('assets/datas/geodata_manifest.json');
    final manifest = jsonDecode(await manifestFile.readAsString());

    expect(manifest, isA<Map>());
    for (final entry in (manifest as Map).entries) {
      final assetFile = File('assets/datas/${entry.key}');
      final metadata = entry.value;

      expect(await assetFile.exists(), isTrue, reason: entry.key.toString());
      expect(metadata, isA<Map>(), reason: entry.key.toString());

      final bytes = await assetFile.readAsBytes();
      expect(
        (metadata as Map)['size'],
        bytes.length,
        reason: entry.key.toString(),
      );
      expect(
        metadata['sha256'],
        sha256.convert(bytes).toString(),
        reason: entry.key.toString(),
      );
    }
  });
}
