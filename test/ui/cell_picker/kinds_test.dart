import 'package:aperture/ui/cell_picker/kinds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // MySQL's COLUMN_TYPE carries a precision or length the Postgres names
  // don't, and its values arrive as text, so the type has to decide.
  test('MySQL column types pick their editors', () {
    expect(kindFor('2024-01-02 03:04:05', 'datetime(3)').id, KindId.datetime);
    expect(kindFor('2024-01-02 03:04:05', 'timestamp').id, KindId.datetime);
    expect(kindFor('03:04:05', 'time').id, KindId.time);
    expect(kindFor('1.50', 'decimal(10,2)').label, 'number');
    expect(kindFor(1.5, 'double').label, 'number');
    expect(kindFor(1, 'int unsigned').label, 'int');
    expect(kindFor('x', 'varbinary(16)').label, 'bytes');
    expect(kindFor('x', 'longblob').label, 'bytes');
    expect(kindFor('x', 'varchar(255)').label, 'string');
  });
}
