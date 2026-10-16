# mysql_dart, vendored

[mysql_dart](https://github.com/insinfo/mysql.dart) 3.0.0 by Isaque Neves,
MIT-licensed (see `LICENSE`), copied here with one change. Only `lib/`,
`LICENSE` and a trimmed `pubspec.yaml` are kept.

## The change

In both result-set loops of `lib/src/mysql_client/connection.dart` (text
protocol and prepared statements), marked `PATCH(aperture)`: an ERR packet
that arrives after rows have started is reported as a
`MySQLServerException` instead of being decoded as a row.

Upstream reads it as a row, throws `MySQLProtocolException: Wrong first
byte, while decoding textual result set row`, and closes the socket. Any
error the server raises mid-stream hits this: `KILL QUERY` (every cancel on
MariaDB, a cancel during a streaming result on MySQL), `max_execution_time`,
or an expression failing on some row.

Drop the copy once a mysql_dart release handles ERR packets in the row loop.
