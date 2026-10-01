import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/services/app_log.dart';

/// 日志页 —— 对应原生 `Fragments/LogFragment.java`。
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final ScrollController _scroll = ScrollController();
  StreamSubscription<void>? _sub;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    // 日志变化时刷新；`_follow` 打开时自动滚到底部。
    _sub = AppLog.instance.changes.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (_follow) _scrollToBottom();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _copyAll() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = AppLog.instance.export();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast(l10n.commonCopied);
  }

  Future<void> _clear() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.logsClearTitle),
        content: Text(l10n.logsClearBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.logsClear),
          ),
        ],
      ),
    );
    if (ok == true) await AppLog.instance.clear();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> lines = AppLog.instance.lines;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logsTitle),
        actions: <Widget>[
          IconButton(
            tooltip: _follow ? l10n.logsFollowOff : l10n.logsFollowOn,
            icon: Icon(_follow ? Icons.vertical_align_bottom : Icons.pause),
            onPressed: () => setState(() => _follow = !_follow),
          ),
          IconButton(
            tooltip: l10n.logsCopyAll,
            onPressed: lines.isEmpty ? null : _copyAll,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: l10n.logsClear,
            onPressed: lines.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              AppLog.instance.enabled
                  ? l10n.logsWrittenTo(AppLog.instance.file?.path ?? '—')
                  : l10n.logsDisabled,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: lines.isEmpty
                ? Center(child: Text(l10n.logsEmpty))
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: lines.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String line = lines[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 1,
                          ),
                          child: SelectableText(
                            line,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.4,
                              color: _colorFor(line, scheme),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(String line, ColorScheme scheme) {
    if (line.contains('[ERROR]')) return scheme.error;
    if (line.contains('[WARN]')) return const Color(0xFFB26A00);
    if (line.contains('[ENGINE]')) return scheme.onSurfaceVariant;
    return scheme.onSurface;
  }
}
