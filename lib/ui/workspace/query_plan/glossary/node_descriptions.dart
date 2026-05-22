/// Plain-English single-sentence descriptions of the operations a
/// Postgres plan can contain. Used as the subtitle of every node card so
/// readers don't need to look up what "Bitmap Heap Scan" means.
const Map<String, String> nodeDescriptions = {
  'Seq Scan': 'Reads every row in the table from start to end.',
  'Index Scan':
      'Walks an index to locate rows, then reads those rows from the table.',
  'Index Only Scan':
      'Walks an index and answers from it directly — no table lookup needed.',
  'Bitmap Index Scan':
      'Builds a bitmap of matching rows from one or more indexes.',
  'Bitmap Heap Scan':
      'Fetches the rows the bitmap pointed at, in disk-block order.',
  'Tid Scan': 'Reads rows by their physical row identifiers.',
  'Sample Scan': 'Reads a random sample of rows from the table.',
  'Subquery Scan': 'Iterates a subquery as if it were a table.',
  'Function Scan': 'Iterates the rows returned by a set-returning function.',
  'Values Scan': 'Reads an inline VALUES list.',
  'CTE Scan': 'Iterates rows produced by a WITH clause.',
  'WorkTable Scan': 'Iterates the working set of a recursive WITH clause.',
  'Foreign Scan': 'Reads rows from a foreign (remote) table.',
  'Nested Loop':
      'For each row on the left, finds the matching rows on the right.',
  'Hash Join':
      'Builds an in-memory hash of one side and probes it from the other.',
  'Merge Join':
      'Merges two sorted inputs together, the way mergesort merges runs.',
  'Hash': 'Builds an in-memory hash table to feed the join above it.',
  'Materialize': 'Caches its input so the parent can scan it more than once.',
  'Sort': 'Sorts its input by the requested keys.',
  'Incremental Sort': 'Sorts within groups that are already partly sorted.',
  'Group': 'Groups consecutive rows with equal keys.',
  'Aggregate': 'Reduces input rows to one row per group (count, sum, …).',
  'WindowAgg': 'Computes window-function values over partitions.',
  'Unique': 'Removes adjacent duplicate rows.',
  'SetOp': 'Computes UNION/INTERSECT/EXCEPT between sorted inputs.',
  'LockRows': 'Locks the rows it sees (FOR UPDATE / SHARE).',
  'Limit': 'Stops emitting rows after the requested number is reached.',
  'Gather': 'Collects rows from parallel worker processes.',
  'Gather Merge':
      'Collects already-sorted rows from parallel workers, in order.',
  'Append': 'Concatenates rows from several child plans (UNION ALL etc.).',
  'Merge Append': 'Concatenates already-sorted inputs in order.',
  'Result': 'Emits a single row, often a computed expression.',
  'ProjectSet': 'Expands a set-returning function in the target list.',
  'ModifyTable': 'Performs the actual INSERT, UPDATE or DELETE.',
  'Recursive Union': 'Drives a recursive CTE to a fixed point.',
};

String describeNode(String kind) {
  return nodeDescriptions[kind] ?? 'A planner operation.';
}
