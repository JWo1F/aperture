import 'package:aperture/models/db_object.dart';
import 'package:aperture/ui/workspace/object_view/plain_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Postgres types read as everyday words', () {
    expect(plainType('integer'), 'Whole number');
    expect(plainType('bigint'), 'Whole number (large)');
    expect(plainType('character varying(80)'), 'Text, up to 80 characters');
    expect(plainType('character(2)'), 'Text, exactly 2 characters');
    expect(plainType('numeric(10,2)'), 'Exact number, 2 decimal places');
    expect(plainType('numeric(10,0)'), 'Whole number');
    expect(plainType('boolean'), 'Yes or no');
    expect(
      plainType('timestamp with time zone'),
      'Date and time, with time zone',
    );
    expect(plainType('timestamp(3) without time zone'), 'Date and time');
    expect(plainType('jsonb'), 'Structured data (JSON)');
    expect(plainType('uuid'), 'Unique identifier');
  });

  test('arrays read as lists', () {
    expect(plainType('text[]'), 'List of text');
    expect(plainType('integer[]'), 'List of whole number');
  });

  test('SQLite declared types follow its affinity rules', () {
    expect(plainType('INTEGER'), 'Whole number');
    expect(plainType('VARCHAR(20)'), 'Text, up to 20 characters');
    expect(plainType('UNSIGNED BIG INT'), 'Whole number');
    expect(plainType('BLOB'), 'File or binary data');
  });

  test('user types read as what they hold', () {
    final enums = [
      DbEnum(schema: 'public', name: 'mood', labels: ['ok', 'sad', 'happy']),
    ];
    final domains = [
      DbDomain(
        schema: 'public',
        name: 'email',
        baseType: 'text',
        notNull: true,
      ),
    ];
    expect(plainType('mood', enums: enums), 'One of: ok, sad or happy');
    expect(plainType('public.mood', enums: enums), 'One of: ok, sad or happy');
    expect(plainType('email', domains: domains), 'Text');
    expect(
      plainType('mood[]', enums: enums),
      'List of one of: ok, sad or happy',
    );
  });

  test('an unknown type comes back as written', () {
    expect(plainType('ltree'), 'ltree');
  });

  test('indexes say what they are for', () {
    expect(
      plainIndex(DbIndex(name: 'i', columns: ['email'], unique: true, def: '')),
      'No two rows can share the same email',
    );
    expect(
      plainIndex(
        DbIndex(
          name: 'i',
          columns: ['last_name', 'first_name'],
          unique: false,
          def: '',
        ),
      ),
      'Quick to find rows by last name and first name',
    );
  });
}
