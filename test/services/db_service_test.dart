import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/services/db_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('versionTag', () {
    test('reduces a plain dotted version to vMAJOR.MINOR', () {
      expect(versionTag('3.45.1'), 'v3.45');
      expect(versionTag('16.4'), 'v16.4');
    });

    test('strips the Postgres build parenthetical', () {
      expect(versionTag('16.4 (Homebrew)'), 'v16.4');
      expect(versionTag('15.2 (Debian 15.2-1.pgdg120+1)'), 'v15.2');
    });

    test('keeps a single segment when no second exists', () {
      expect(versionTag('17'), 'v17');
    });

    test('trims surrounding whitespace', () {
      expect(versionTag('  3.45.1\n'), 'v3.45');
    });

    test('returns null for empty / whitespace-only input', () {
      expect(versionTag(''), isNull);
      expect(versionTag('   '), isNull);
    });
  });

  group('timedEdit', () {
    test('returns the apply result and reports a null-error log', () async {
      final batch = EditBatch(
        updatesByCtid: {
          '1': {'a': const CellLiteral('x')},
        },
      );
      int? loggedStatementCount;
      String? loggedError;
      Duration? loggedElapsed;

      final result = await timedEdit(
        batch: batch,
        logger:
            ({
              required int statementCount,
              required Duration elapsed,
              required String? error,
            }) {
              loggedStatementCount = statementCount;
              loggedElapsed = elapsed;
              loggedError = error;
            },
        apply: () async => const EditResult.success(1),
      );

      expect(result.ok, isTrue);
      expect(result.appliedCount, 1);
      expect(loggedStatementCount, batch.statementCount);
      expect(loggedError, isNull);
      expect(loggedElapsed, isNotNull);
    });

    test('forwards a failure result and logs the engine error', () async {
      final batch = EditBatch(deleteCtids: const ['1', '2']);
      String? loggedError;

      final result = await timedEdit(
        batch: batch,
        logger:
            ({
              required int statementCount,
              required Duration elapsed,
              required String? error,
            }) {
              loggedError = error;
            },
        apply: () async => const EditResult.failure(
          appliedCount: 1,
          totalCount: 2,
          error: 'boom',
        ),
      );

      expect(result.ok, isFalse);
      expect(result.partial, isTrue);
      expect(result.error, 'boom');
      expect(loggedError, 'boom');
    });

    test('still works with a null logger', () async {
      final result = await timedEdit(
        batch: EditBatch(),
        logger: null,
        apply: () async => const EditResult.success(0),
      );
      expect(result.ok, isTrue);
      expect(result.totalCount, 0);
    });
  });
}
