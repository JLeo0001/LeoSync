import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/controllers/task_controller.dart';
import '../../core/models/sync_filter.dart';

/// 过滤规则管理 —— 对应原生 `Fragments/FilterEntryRecyclerViewAdapter`
/// 与 `Activities/FilterActivity.kt`。
///
/// 规则语法与 engine `--filter` 完全一致，界面上提供「包含 / 排除」两个按钮
/// 和常用模板，避免用户去记语法。
class FilterEditPage extends StatelessWidget {
  const FilterEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TaskController controller = context.watch<TaskController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.filtersTitle)),
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.filtersHint,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const Divider(height: 1),
          if (controller.filters.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(l10n.filtersEmptyList, textAlign: TextAlign.center),
            )
          else
            ...controller.filters.map(
              (SyncFilter filter) => ListTile(
                leading: const Icon(Icons.filter_alt_outlined),
                title: Text(
                  filter.title.isEmpty ? l10n.filtersUntitled : filter.title,
                ),
                subtitle: Text(
                  filter.entries.isEmpty
                      ? l10n.filtersEmptyEntries
                      : filter.entries
                          .take(3)
                          .map((FilterEntry e) => e.toEngineValue())
                          .join('  ·  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(
                    controller.deleteFilter(filter.id),
                  ),
                ),
                onTap: () => unawaited(_edit(context, controller, filter)),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => unawaited(_edit(context, controller, null)),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    TaskController controller,
    SyncFilter? existing,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => _FilterDetailPage(existing: existing),
      ),
    );
    await controller.load();
  }
}

class _FilterDetailPage extends StatefulWidget {
  const _FilterDetailPage({this.existing});

  final SyncFilter? existing;

  @override
  State<_FilterDetailPage> createState() => _FilterDetailPageState();
}

class _FilterDetailPageState extends State<_FilterDetailPage> {
  /// 便捷取用本地化文案。
  AppLocalizations get l10n => AppLocalizations.of(context);

  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final List<FilterEntry> _entries =
      List<FilterEntry>.of(widget.existing?.entries ?? const <FilterEntry>[]);

  /// 常用模板 —— 原生没有，但能显著降低使用门槛。
  static const List<FilterEntry> _templates = <FilterEntry>[
    FilterEntry(isInclude: false, pattern: '*.tmp'),
    FilterEntry(isInclude: false, pattern: '.git/**'),
    FilterEntry(isInclude: false, pattern: '/.**'),
    FilterEntry(isInclude: true, pattern: '*'),
  ];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _addEntry() async {
    final TextEditingController controller = TextEditingController();
    bool include = true;
    final FilterEntry? result = await showDialog<FilterEntry>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocalState) =>
            AlertDialog(
          title: Text(l10n.filtersAddRule),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text(l10n.filtersInclude)),
                  ButtonSegment<bool>(value: false, label: Text(l10n.filtersExclude)),
                ],
                selected: <bool>{include},
                onSelectionChanged: (Set<bool> value) =>
                    setLocalState(() => include = value.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.filtersPattern,
                  hintText: '*.tmp 或 /photos/**',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final String pattern = controller.text.trim();
                if (pattern.isEmpty) return;
                Navigator.of(context).pop(
                  FilterEntry(isInclude: include, pattern: pattern),
                );
              },
              child: Text(l10n.commonAdd),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) {
      setState(() => _entries.add(result));
    }
  }

  Future<void> _save() async {
    final SyncFilter filter = SyncFilter(
      id: widget.existing?.id ?? 0,
      title: _title.text.trim(),
      entries: List<FilterEntry>.unmodifiable(_entries),
    );
    await context.read<TaskController>().saveFilter(filter);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? l10n.filtersNew : l10n.filtersEdit,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => unawaited(_save()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: l10n.filtersName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.filtersRules,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l10n.filtersEmpty,
                style: const TextStyle(fontSize: 12),
              ),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (int oldIndex, int newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  _entries.insert(newIndex, _entries.removeAt(oldIndex));
                });
              },
              children: _entries
                  .map(
                    (FilterEntry entry) => ListTile(
                      key: ValueKey<String>(
                        '${entry.isInclude}-${entry.pattern}-'
                        '${_entries.indexOf(entry)}',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        entry.isInclude
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                        color: entry.isInclude ? Colors.green : Colors.redAccent,
                      ),
                      title: Text(entry.pattern),
                      subtitle: Text(
                        entry.isInclude ? l10n.filtersInclude : l10n.filtersExclude,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: l10n.filtersToggle,
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            onPressed: () => setState(() {
                              final int i = _entries.indexOf(entry);
                              _entries[i] = entry.toggle();
                            }),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _entries.remove(entry)),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => unawaited(_addEntry()),
            icon: const Icon(Icons.add),
            label: Text(l10n.filtersAddRule),
          ),
          const SizedBox(height: 24),
          Text(l10n.filtersTemplates,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _templates
                .map(
                  (FilterEntry template) => ActionChip(
                    avatar: Icon(
                      template.isInclude
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                      size: 16,
                    ),
                    label: Text(template.pattern),
                    onPressed: () => setState(() => _entries.add(template)),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}
