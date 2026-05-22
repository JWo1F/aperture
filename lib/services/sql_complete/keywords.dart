/// Static keyword sets for the SQL autocomplete engine, grouped by the
/// clause / statement slot they belong to. Pure data — the completers
/// pick a list and the ranker scores it against the typed token.
library;

const List<String> statementKeywords = [
  'SELECT',
  'INSERT INTO',
  'UPDATE',
  'DELETE FROM',
  'WITH',
  'CREATE',
  'ALTER',
  'DROP',
  'TRUNCATE',
  'EXPLAIN',
];

const List<String> selectListKeywords = [
  'DISTINCT',
  'ALL',
  'AS',
  'CASE',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
  'COUNT(*)',
  'NULL',
  'TRUE',
  'FALSE',
  'FROM',
];

const List<String> selectTailKeywords = [
  'WHERE',
  'GROUP BY',
  'ORDER BY',
  'HAVING',
  'LIMIT',
  'OFFSET',
  'JOIN',
  'INNER JOIN',
  'LEFT JOIN',
  'RIGHT JOIN',
  'FULL JOIN',
  'CROSS JOIN',
  'UNION',
  'INTERSECT',
  'EXCEPT',
];

const List<String> whereKeywords = [
  'AND',
  'OR',
  'NOT',
  'IS',
  'IS NULL',
  'IS NOT NULL',
  'IN',
  'BETWEEN',
  'LIKE',
  'ILIKE',
  'EXISTS',
  'ANY',
  'ALL',
  'NULL',
  'TRUE',
  'FALSE',
  'CASE',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
];

const List<String> orderKeywords = [
  'ASC',
  'DESC',
  'NULLS FIRST',
  'NULLS LAST',
];

const List<String> joinTailKeywords = ['ON', 'USING', 'AS'];

// Re-exported for the clause-bar in table_view (single-line inputs).
const List<String> selectModifierKeywords = ['DISTINCT', 'AS', 'COUNT(*)'];

const List<String> whereOperatorKeywords = whereKeywords;

const List<String> orderModifierKeywords = orderKeywords;
