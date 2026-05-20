import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/query_result.dart';
import '../../services/exporter.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Describes one thing the user can export.
///
/// `currentResult` is what's already loaded into the grid. `fetchAll` (when
/// provided) lets the dialog re-fetch every matching row from the database
/// for the "All filtered rows" scope.
class ExportTarget {
  ExportTarget({
    required this.suggestedFilename,
    required this.currentResult,
    this.fetchAll,
    this.totalRowsForAll,
  });

  final String suggestedFilename;
  final QueryResult currentResult;
  final Future<QueryResult> Function()? fetchAll;
  final int? totalRowsForAll;

  bool get hasAllScope => fetchAll != null;
}

enum _Scope { current, all }

Future<void> showExportDialog(
  BuildContext context, {
  required ExportTarget target,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x88000000),
    builder: (_) => Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.brLg,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _ExportBody(target: target),
      ),
    ),
  );
}

class _ExportBody extends StatefulWidget {
  const _ExportBody({required this.target});
  final ExportTarget target;

  @override
  State<_ExportBody> createState() => _ExportBodyState();
}

class _ExportBodyState extends State<_ExportBody> {
  ExportFormat _format = exportFormats.first;
  late _Scope _scope;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = widget.target.hasAllScope ? _Scope.all : _Scope.current;
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // 1. Resolve what to write (existing result or fetch all).
      final QueryResult data;
      if (_scope == _Scope.all && widget.target.fetchAll != null) {
        data = await widget.target.fetchAll!();
      } else {
        data = widget.target.currentResult;
      }

      // 2. Ask the OS for a save location.
      final suggested = _swapExtension(
        widget.target.suggestedFilename,
        _format.fileExtension,
      );
      final FileSaveLocation? location;
      try {
        location = await getSaveLocation(
          suggestedName: suggested,
          acceptedTypeGroups: [
            XTypeGroup(
              label: _format.label,
              extensions: [_format.fileExtension],
            ),
          ],
        );
      } catch (e) {
        setState(() {
          _busy = false;
          _error = 'Save dialog failed: $e';
        });
        return;
      }

      if (location == null) {
        // User cancelled the save dialog — keep our dialog open so they can retry.
        if (mounted) setState(() => _busy = false);
        return;
      }

      // 3. Write the file.
      await _format.writeFile(File(location.path), data);

      navigator.pop();
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceAlt,
          content: Text(
            'Exported ${data.rows.length} row${data.rows.length == 1 ? '' : 's'} to ${location.path}',
            style: AppTheme.mono(size: 11.5, color: AppColors.textPrimary),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  String _swapExtension(String filename, String extension) {
    final dot = filename.lastIndexOf('.');
    final stem = dot == -1 ? filename : filename.substring(0, dot);
    return '$stem.$extension';
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final allCount = target.totalRowsForAll ?? 0;
    final currentCount = target.currentResult.rows.length;

    return Padding(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.ios_share,
                size: 14,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Export',
                style: AppTheme.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Save the result set to a file.',
            style: AppTheme.ui(size: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: Insets.lg),
          Text('FORMAT', style: AppTheme.eyebrow()),
          const SizedBox(height: 6),
          _FormatChips(
            selected: _format,
            onSelect: (f) => setState(() => _format = f),
          ),
          if (target.hasAllScope) ...[
            const SizedBox(height: Insets.lg),
            Text('SCOPE', style: AppTheme.eyebrow()),
            const SizedBox(height: 6),
            _ScopeChoice(
              scope: _Scope.current,
              selected: _scope,
              label: 'Current page',
              hint: '$currentCount row${currentCount == 1 ? '' : 's'} '
                  'already loaded',
              onSelect: () => setState(() => _scope = _Scope.current),
            ),
            const SizedBox(height: 6),
            _ScopeChoice(
              scope: _Scope.all,
              selected: _scope,
              label: 'All filtered rows',
              hint: '~$allCount row${allCount == 1 ? '' : 's'} '
                  '(re-fetched from the database)',
              onSelect: () => setState(() => _scope = _Scope.all),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Insets.md),
            Container(
              padding: const EdgeInsets.all(Insets.sm),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: Radii.brSm,
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 13, color: AppColors.error),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _error!,
                      style: AppTheme.mono(
                        size: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Insets.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancel',
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: Insets.sm),
              AppButton(
                label: _busy ? 'Exporting…' : 'Export…',
                icon: Icons.save_alt,
                primary: true,
                onPressed: _busy ? null : _export,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormatChips extends StatelessWidget {
  const _FormatChips({required this.selected, required this.onSelect});
  final ExportFormat selected;
  final ValueChanged<ExportFormat> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        for (final f in exportFormats)
          _FormatChip(
            format: f,
            selected: f.id == selected.id,
            onTap: () => onSelect(f),
          ),
      ],
    );
  }
}

class _FormatChip extends StatefulWidget {
  const _FormatChip({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FormatChip> createState() => _FormatChipState();
}

class _FormatChipState extends State<_FormatChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : (_hover ? AppColors.surfaceHover : AppColors.bg),
            borderRadius: Radii.brSm,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            widget.format.label,
            style: AppTheme.mono(
              size: 11.5,
              color: selected ? AppColors.accent : AppColors.textSecondary,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeChoice extends StatefulWidget {
  const _ScopeChoice({
    required this.scope,
    required this.selected,
    required this.label,
    required this.hint,
    required this.onSelect,
  });

  final _Scope scope;
  final _Scope selected;
  final String label;
  final String hint;
  final VoidCallback onSelect;

  @override
  State<_ScopeChoice> createState() => _ScopeChoiceState();
}

class _ScopeChoiceState extends State<_ScopeChoice> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.scope == widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : (_hover ? AppColors.surfaceHover : AppColors.bg),
            borderRadius: Radii.brSm,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.accent
                        : AppColors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: AppTheme.ui(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      widget.hint,
                      style: AppTheme.mono(
                        size: 10.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
