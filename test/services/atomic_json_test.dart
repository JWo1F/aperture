import 'dart:io';

import 'package:aperture/services/atomic_json.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _StubPathProvider extends PathProviderPlatform {
  _StubPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('atomic_json_test');
    PathProviderPlatform.instance = _StubPathProvider(dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('save then load round-trips JSON shape', () async {
    final file = AtomicJsonFile('round.json');
    await file.save({'a': 1, 'b': 'two'});
    final loaded = await file.load();
    expect(loaded, isA<Map>());
    expect((loaded as Map)['a'], 1);
    expect(loaded['b'], 'two');
  });

  test('load returns null for missing file', () async {
    final file = AtomicJsonFile('nope.json');
    final loaded = await file.load();
    expect(loaded, isNull);
  });

  test('save writes through a temp file and renames atomically', () async {
    final file = AtomicJsonFile('atomic.json');
    await file.save([1, 2, 3]);
    final tmp = File('${dir.path}/atomic.json.tmp');
    expect(await tmp.exists(), isFalse);
    final live = File('${dir.path}/atomic.json');
    expect(await live.exists(), isTrue);
  });

  test('corrupt JSON moves the file to .bak.<ts> and returns null',
      () async {
    final file = AtomicJsonFile('corrupt.json');
    final raw = File('${dir.path}/corrupt.json');
    await raw.writeAsString('{ not valid json');
    final loaded = await file.load();
    expect(loaded, isNull);
    final entries = await dir.list().toList();
    final hasBak = entries.any((e) => e.path.contains('corrupt.json.bak.'));
    expect(hasBak, isTrue);
  });
}
