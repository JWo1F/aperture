import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

enum _Destination { file, clipboard }

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
  _Destination _destination = _Destination.file;
  bool _busy = false;
  String? _error;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _scope = widget.target.hasAllScope ? _Scope.all : _Scope.current;
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    final cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
      _cancel = cancel;
    });

    try {
      // 1. Resolve what to write (existing result or fetch all).
      final QueryResult data;
      if (_scope == _Scope.all && widget.target.fetchAll != null) {
        data = await widget.target.fetchAll!();
      } else {
        data = widget.target.currentResult;
      }

      // 2. Dispatch by destination.
      final String snackText;
      if (_destination == _Destination.clipboard) {
        await Clipboard.setData(ClipboardData(text: _format.render(data)));
        snackText =
            'Copied ${data.rows.length} row${data.rows.length == 1 ? '' : 's'} '
            'as ${_format.label} to the clipboard';
      } else {
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

        await _format.writeFile(File(location.path), data, cancel: cancel);
        snackText =
            'Exported ${data.rows.length} row${data.rows.length == 1 ? '' : 's'} '
            'to ${location.path}';
      }

      navigator.pop();
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceAlt,
          content: Text(
            snackText,
            style: AppTheme.mono(size: 11.5, color: AppColors.textPrimary),
          ),
        ),
      );
    } on ExportCancelledException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _cancel = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _cancel = null;
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
              Icon(Icons.ios_share, size: 14, color: AppColors.accent),
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
            _destination == _Destination.clipboard
                ? 'Copy the result set to the clipboard.'
                : 'Save the result set to a file.',
            style: AppTheme.ui(size: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: Insets.lg),
          Text('FORMAT', style: AppTheme.eyebrow()),
          const SizedBox(height: 6),
          _FormatChips(
            selected: _format,
            onSelect: (f) => setState(() => _format = f),
          ),
          const SizedBox(height: Insets.lg),
          Text('DESTINATION', style: AppTheme.eyebrow()),
          const SizedBox(height: 6),
          _DestinationChips(
            selected: _destination,
            onSelect: (d) => setState(() => _destination = d),
          ),
          if (target.hasAllScope) ...[
            const SizedBox(height: Insets.lg),
            Text('SCOPE', style: AppTheme.eyebrow()),
            const SizedBox(height: 6),
            _ScopeChoice(
              scope: _Scope.current,
              selected: _scope,
              label: 'Current page',
              hint:
                  '$currentCount row${currentCount == 1 ? '' : 's'} '
                  'already loaded',
              onSelect: () => setState(() => _scope = _Scope.current),
            ),
            const SizedBox(height: 6),
            _ScopeChoice(
              scope: _Scope.all,
              selected: _scope,
              label: 'All filtered rows',
              hint:
                  '~$allCount row${allCount == 1 ? '' : 's'} '
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
                  Icon(Icons.error_outline, size: 13, color: AppColors.error),
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
                label: _busy ? 'Stop export' : 'Cancel',
                onPressed: _busy
                    ? () => _cancel?.cancel()
                    : () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: Insets.sm),
              AppButton(
                label: _busy
                    ? (_destination == _Destination.clipboard
                          ? 'Copying…'
                          : 'Exporting…')
                    : (_destination == _Destination.clipboard
                          ? 'Copy'
                          : 'Export…'),
                icon: _destination == _Destination.clipboard
                    ? Icons.content_copy
                    : Icons.save_alt,
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

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : (hovering ? AppColors.surfaceHover : AppColors.bg),
          borderRadius: Radii.brSm,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          format.label,
          style: AppTheme.mono(
            size: 11.5,
            color: selected ? AppColors.accent : AppColors.textSecondary,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DestinationChips extends StatelessWidget {
  const _DestinationChips({required this.selected, required this.onSelect});

  final _Destination selected;
  final ValueChanged<_Destination> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        _DestinationChip(
          destination: _Destination.file,
          selected: selected == _Destination.file,
          label: 'File',
          icon: Icons.insert_drive_file_outlined,
          onTap: () => onSelect(_Destination.file),
        ),
        _DestinationChip(
          destination: _Destination.clipboard,
          selected: selected == _Destination.clipboard,
          label: 'Clipboard',
          icon: Icons.content_copy,
          onTap: () => onSelect(_Destination.clipboard),
        ),
      ],
    );
  }
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.destination,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : (hovering ? AppColors.surfaceHover : AppColors.bg),
          borderRadius: Radii.brSm,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.mono(
                size: 11.5,
                color: selected ? AppColors.accent : AppColors.textSecondary,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeChoice extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isSelected = scope == selected;
    return Hoverable(
      onTap: onSelect,
      builder: (context, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentSoft
              : (hovering ? AppColors.surfaceHover : AppColors.bg),
          borderRadius: Radii.brSm,
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
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
                  color: isSelected ? AppColors.accent : AppColors.borderStrong,
                  width: 1.5,
                ),
              ),
              child: isSelected
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
                    label,
                    style: AppTheme.ui(
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    hint,
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
    );
  }
}
