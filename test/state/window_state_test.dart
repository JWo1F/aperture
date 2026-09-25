import 'dart:io';

import 'package:aperture/services/store_database.dart';
import 'package:aperture/services/window_frame.dart';
import 'package:aperture/state/app_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWindow extends WindowFrame {
  Map<String, double> frame = {'x': 10, 'y': 20, 'w': 1200, 'h': 800};
  bool fullScreen = false;
  final calls = <String>[];

  @override
  Future<({Map<String, double> frame, bool fullScreen})?> read() async =>
      (frame: Map.of(frame), fullScreen: fullScreen);

  @override
  Future<void> write(Map<String, double> frame) async {
    calls.add('frame ${frame['w']}x${frame['h']}');
    this.frame = Map.of(frame);
  }

  @override
  Future<void> setFullScreen(bool fullScreen) async {
    calls.add('fullScreen $fullScreen');
    this.fullScreen = fullScreen;
  }
}

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('window_state');
    path = '${dir.path}/store.sqlite';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppStore storeOn(_FakeWindow window) {
    final store = AppStore(window: window)
      ..open(StoreDatabase.open(path, 'pw'));
    addTearDown(store.dispose);
    return store;
  }

  test('frame and full screen survive a relaunch, restored in order', () async {
    final before = _FakeWindow();
    final a = storeOn(before);
    before.frame = {'x': 100, 'y': 50, 'w': 1440, 'h': 900};
    await a.captureWindowFrame();
    before
      ..fullScreen = true
      ..frame = {'x': 0, 'y': 0, 'w': 3024, 'h': 1964};
    await a.captureWindowFrame();
    await a.flush();

    final after = _FakeWindow();
    storeOn(after);
    await Future<void>.delayed(Duration.zero);
    expect(after.calls, ['frame 1440.0x900.0', 'fullScreen true']);
  });

  test('leaving full screen records the windowed state again', () async {
    final window = _FakeWindow()..fullScreen = true;
    final a = storeOn(window);
    await a.captureWindowFrame();
    window
      ..fullScreen = false
      ..frame = {'x': 5, 'y': 5, 'w': 1000, 'h': 700};
    await a.captureWindowFrame();
    await a.flush();

    final after = _FakeWindow();
    storeOn(after);
    await Future<void>.delayed(Duration.zero);
    expect(after.calls, ['frame 1000.0x700.0']);
  });

  test('a store that never saw the window leaves it alone', () async {
    final window = _FakeWindow();
    storeOn(window);
    await Future<void>.delayed(Duration.zero);
    expect(window.calls, isEmpty);
  });
}
