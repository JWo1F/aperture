enum AdviceSeverity { good, info, warn, critical }

class Advice {
  Advice({required this.severity, required this.title, required this.body});

  final AdviceSeverity severity;
  final String title;
  final String body;
}
