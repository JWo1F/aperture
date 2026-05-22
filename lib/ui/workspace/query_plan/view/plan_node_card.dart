import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../analysis/advice_engine.dart';
import '../glossary/node_descriptions.dart';
import '../model/plan_node.dart';
import 'rail_painter.dart';

/// One row in the plan-tree list: an indent rail to the left, a card
/// describing the node to the right. The card's right edge always lands
/// at the same x regardless of indent depth so the ms / % column is
/// aligned across the whole stack.
class PlanNodeCard extends StatelessWidget {
  const PlanNodeCard({
    super.key,
    required this.node,
    required this.totalMs,
    required this.isSlowest,
  });

  final PlanNode node;
  final double totalMs;
  final bool isSlowest;

  static const double _indentStep = 22;

  @override
  Widget build(BuildContext context) {
    final fraction = totalMs > 0 ? (node.selfMs / totalMs) : 0.0;
    final pct = (fraction * 100).round();
    final cardColor = isSlowest
        ? AppColors.warning.withValues(alpha: 0.06)
        : AppColors.surface;
    final borderColor = isSlowest
        ? AppColors.warning.withValues(alpha: 0.4)
        : AppColors.border;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (node.depth > 0)
              SizedBox(
                width: node.depth * _indentStep,
                child: IndentRail(node: node, indentStep: _indentStep),
              ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: cardColor,
                  border: Border.all(color: borderColor),
                  borderRadius: Radii.brMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (node.relationshipLabel != null) ...[
                      _RelationshipKicker(
                        label: node.relationshipLabel!,
                        parentType: node.parentType,
                      ),
                      const SizedBox(height: 4),
                    ],
                    _CardHeader(node: node, pct: pct, isSlowest: isSlowest),
                    const SizedBox(height: 4),
                    Text(
                      describeNode(node.kind),
                      style: AppTheme.mono(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (node.conditions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final c in node.conditions)
                            _ConditionChip(label: c.$1, value: c.$2),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    _MetricsRow(node: node, pct: pct),
                    const SizedBox(height: 6),
                    _TimeBar(fraction: fraction, isSlowest: isSlowest),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny breadcrumb above a card's header that names this node's role
/// inside its parent ("hash input ↑ Hash Join"). Disambiguates levels
/// of the tree so the indent stops being the only hierarchy cue.
class _RelationshipKicker extends StatelessWidget {
  const _RelationshipKicker({required this.label, required this.parentType});

  final String label;
  final String? parentType;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.mono(
      size: 9.5,
      color: AppColors.textMuted,
      weight: FontWeight.w500,
    ).copyWith(letterSpacing: 0.4);
    final emph = AppTheme.mono(
      size: 9.5,
      color: AppColors.textSecondary,
      weight: FontWeight.w600,
    ).copyWith(letterSpacing: 0.4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.arrow_upward, size: 10, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Flexible(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(text: label.toUpperCase(), style: muted),
                if (parentType != null) ...[
                  TextSpan(text: '  →  ', style: muted),
                  TextSpan(text: parentType!.toUpperCase(), style: emph),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.node,
    required this.pct,
    required this.isSlowest,
  });

  final PlanNode node;
  final int pct;
  final bool isSlowest;

  @override
  Widget build(BuildContext context) {
    final target = node.target;
    // Self time, not the inclusive subtree total — the headline figure,
    // the % chip and the bar all describe the work done in this node
    // alone, so the "slowest" card is also the one with the fullest bar.
    final analyzed = node.actualTotalTime != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        NodeBadge(type: node.kind, small: false),
        if (target != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              target,
              style: AppTheme.mono(size: 12, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (isSlowest) ...[const SizedBox(width: 8), const _SlowestPill()],
        const Spacer(),
        if (analyzed) ...[
          Text(
            '${node.selfMs.toStringAsFixed(2)} ms',
            style: AppTheme.mono(
              size: 12,
              color: AppColors.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          _PercentChip(pct: pct),
        ] else if (node.totalCost != null) ...[
          Text(
            'cost ${node.selfMs.toStringAsFixed(1)}',
            style: AppTheme.mono(size: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _SlowestPill extends StatelessWidget {
  const _SlowestPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'slowest',
        style: AppTheme.mono(
          size: 9.5,
          color: AppColors.warning,
          weight: FontWeight.w600,
        ).copyWith(letterSpacing: 0.4),
      ),
    );
  }
}

class _PercentChip extends StatelessWidget {
  const _PercentChip({required this.pct});

  final int pct;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (pct >= 60) {
      color = AppColors.warning;
    } else if (pct >= 25) {
      color = AppColors.accent;
    } else {
      color = AppColors.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$pct%',
        style: AppTheme.mono(size: 10, color: color, weight: FontWeight.w600),
      ),
    );
  }
}

/// Operation-kind badge: a coloured pill carrying the node type. Tinted
/// by family (joins / scans / aggregates / sorts / hash) so the eye picks
/// up shape without reading the label. Also used by the summary header.
class NodeBadge extends StatelessWidget {
  const NodeBadge({super.key, required this.type, required this.small});

  final String type;
  final bool small;

  Color _color() {
    final t = type.toLowerCase();
    if (t.contains('join')) return AppColors.accent;
    if (t.contains('scan')) return AppColors.sqlKeyword;
    if (t.contains('aggregate') ||
        t.contains('group') ||
        t.contains('window')) {
      return AppColors.sqlFunction;
    }
    if (t.contains('sort') || t.contains('limit')) {
      return AppColors.sqlString;
    }
    if (t.contains('hash')) return AppColors.accent;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final size = small ? 10.5 : 12.0;
    final pad = small ? 5.0 : 7.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type,
        style: AppTheme.mono(size: size, color: color, weight: FontWeight.w600),
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTheme.mono(size: 10.5, color: AppColors.textPrimary),
          children: [
            TextSpan(
              text: '$label ',
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.node, required this.pct});

  final PlanNode node;
  final int pct;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    final actual = node.actualRows;
    final est = node.planRows;
    if (actual != null) {
      segments.add(_Metric(label: 'rows', value: formatInt(actual)));
      if (est != null) {
        segments.add(
          _Metric(label: 'estimated', value: formatInt(est), muted: true),
        );
      }
    } else if (est != null) {
      segments.add(_Metric(label: 'rows est', value: formatInt(est)));
    }
    final loops = node.actualLoops;
    if (loops != null && loops > 1) {
      segments.add(_Metric(label: 'loops', value: '$loops'));
    }

    final mismatch = node.mismatch;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          segments[i],
          if (i != segments.length - 1) const SizedBox(width: 12),
        ],
        if (mismatch != PlanMismatch.none) ...[
          if (segments.isNotEmpty) const SizedBox(width: 12),
          _MismatchChip(severity: mismatch, actual: actual, estimated: est),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: AppTheme.mono(size: 11, color: AppColors.textMuted),
        children: [
          TextSpan(
            text: value,
            style: AppTheme.mono(
              size: 11,
              color: muted ? AppColors.textMuted : AppColors.textPrimary,
              weight: muted ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
    );
  }
}

class _MismatchChip extends StatelessWidget {
  const _MismatchChip({
    required this.severity,
    required this.actual,
    required this.estimated,
  });

  final PlanMismatch severity;
  final int? actual;
  final int? estimated;

  @override
  Widget build(BuildContext context) {
    final color = severity == PlanMismatch.severe
        ? AppColors.error
        : AppColors.warning;
    final label = severity == PlanMismatch.severe
        ? 'estimate way off'
        : 'estimate off';
    final tip = (actual == null || estimated == null)
        ? label
        : '$label · expected $estimated, got $actual';
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_outlined, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: AppTheme.mono(
                size: 9.5,
                color: color,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeBar extends StatelessWidget {
  const _TimeBar({required this.fraction, required this.isSlowest});

  final double fraction;
  final bool isSlowest;

  @override
  Widget build(BuildContext context) {
    final clamped = fraction.clamp(0.0, 1.0).toDouble();
    final fillColor = isSlowest
        ? AppColors.warning
        : clamped >= 0.6
        ? AppColors.warning
        : clamped >= 0.25
        ? AppColors.accent
        : AppColors.accent.withValues(alpha: 0.55);
    return Stack(
      children: [
        Container(
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            height: 5,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    );
  }
}
