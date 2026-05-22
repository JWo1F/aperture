/// SQL autocomplete engine — public surface.
///
/// The implementation is split into focused modules under `sql_complete/`:
///
///   * `text_scan`        — string/comment scanning, cursor word lookups
///   * `keywords`         — static keyword / data-type / constraint sets
///   * `scope`            — FROM/JOIN/INTO reference resolution (`SqlScope`)
///   * `clause`           — clause + statement-kind detection
///   * `suggestions`      — `CodeSuggestion` builders + relevance ranking
///   * `select_completer` — SELECT and shared read-clause completion
///   * `insert_completer` — INSERT (column list, VALUES, ON CONFLICT, …)
///   * `ddl_completer`    — CREATE / ALTER / DROP / TRUNCATE
///   * `query_completer`  — orchestrator that dispatches to the above
///
/// Callers only need this barrel; the modules import each other directly.
library;

export 'sql_complete/clause.dart' show SqlClause, detectClause;
export 'sql_complete/keywords.dart'
    show orderModifierKeywords, selectModifierKeywords, whereOperatorKeywords;
export 'sql_complete/query_completer.dart'
    show completeClause, completeQueryEditor;
export 'sql_complete/scope.dart' show SqlScope, parseScope;
export 'sql_complete/text_scan.dart'
    show
        isInsideStringOrComment,
        previousWord,
        qualifierBefore,
        qualifierChainBefore;
