import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/services/mysql_table_repository.dart';
import 'package:aperture/services/sql_identifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final table = DbTable(
    oid: 1,
    schema: 'shop',
    name: 'line_items',
    kind: DbRelationKind.table,
    dialect: SqlDialect.mysql,
  );

  // A row identity names its key columns, so the predicate needs no
  // catalog lookup and the preview can render it synchronously.
  test('addresses a row by every column of its primary key', () {
    final stmts = buildMysqlEditStatements(
      table,
      EditBatch(
        updatesByCtid: {
          '[["order_id","7"],["sku","it\'s"]]': {'qty': const CellLiteral('3')},
        },
      ),
    );
    expect(stmts, [
      'UPDATE `shop`.`line_items` SET\n'
          "  `qty` = '3'\n"
          "WHERE `order_id` = '7' AND `sku` = 'it''s'",
    ]);
  });

  test('keeps DEFAULT in both UPDATE and INSERT', () {
    final stmts = buildMysqlEditStatements(
      table,
      EditBatch(
        updatesByCtid: {
          '[["order_id","7"]]': {'qty': const CellDefault()},
        },
        inserts: [
          PendingInsert(
            values: {
              'order_id': const CellDefault(),
              'qty': const CellLiteral('1'),
            },
          ),
        ],
      ),
    );
    expect(stmts, [
      'UPDATE `shop`.`line_items` SET\n'
          '  `qty` = DEFAULT\n'
          "WHERE `order_id` = '7'",
      'INSERT INTO `shop`.`line_items` (`order_id`, `qty`)\n'
          "VALUES (DEFAULT, '1')",
    ]);
  });

  test('deletes by key', () {
    final stmts = buildMysqlEditStatements(
      table,
      EditBatch(deleteCtids: ['[["order_id","9"]]']),
    );
    expect(stmts, ["DELETE FROM `shop`.`line_items`\nWHERE `order_id` = '9'"]);
  });
}
