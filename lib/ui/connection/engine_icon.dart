import 'package:flutter/widgets.dart';

import '../../models/connection_config.dart';
import '../../theme/hugeicons.dart';

/// The glyph that stands for [engine] in the connection dialog and the
/// sidebar's connection card.
IconData engineIcon(DbEngine engine) => switch (engine) {
  DbEngine.postgres => Hgi.serverStack01,
  DbEngine.mysql => Hgi.serverStack02,
  DbEngine.sqlite => Hgi.file01,
};
