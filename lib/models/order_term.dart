/// One column in an `ORDER BY` clause.
class OrderTerm {
  const OrderTerm(this.column, this.descending);

  final String column;
  final bool descending;
}

final _identifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

String _quote(String column) =>
    _identifier.hasMatch(column) ? '"$column"' : column;

/// Parses an `ORDER BY` fragment into structured terms. Lenient: anything it
/// cannot interpret as a trailing ASC/DESC is treated as part of the column
/// expression.
List<OrderTerm> parseOrderBy(String raw) {
  final terms = <OrderTerm>[];
  for (final part in raw.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;

    final tokens = trimmed.split(RegExp(r'\s+'));
    var descending = false;
    var columnTokens = tokens;
    if (tokens.length > 1) {
      final last = tokens.last.toUpperCase();
      if (last == 'DESC' || last == 'ASC') {
        descending = last == 'DESC';
        columnTokens = tokens.sublist(0, tokens.length - 1);
      }
    }
    final column = columnTokens.join(' ').replaceAll('"', '');
    if (column.isNotEmpty) terms.add(OrderTerm(column, descending));
  }
  return terms;
}

/// Renders structured terms back into a canonical `ORDER BY` fragment.
String renderOrderBy(List<OrderTerm> terms) => terms
    .map((t) => '${_quote(t.column)} ${t.descending ? 'DESC' : 'ASC'}')
    .join(', ');

/// Cycles a column through the sort states: absent → ASC → DESC → absent.
/// Other columns keep their place and direction.
List<OrderTerm> cycleOrder(List<OrderTerm> terms, String column) {
  final next = List<OrderTerm>.of(terms);
  final index = next.indexWhere((t) => t.column == column);
  if (index == -1) {
    next.add(OrderTerm(column, false));
  } else if (!next[index].descending) {
    next[index] = OrderTerm(column, true);
  } else {
    next.removeAt(index);
  }
  return next;
}
