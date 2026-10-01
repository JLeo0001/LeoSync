import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/controllers/engine_controller.dart';
import '../../core/controllers/task_controller.dart';
import '../../core/models/sync_task.dart';
import 'task_edit_page.dart';
import 'triggers_page.dart';

/// 同步任务列表 —— 对应原生 `Fragments/TasksFragment.java`。
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final TaskController tasks = context.read<TaskController>();
    // 任务需要远端列表来解析 remoteId，这里同步一份快照。
    tasks.remotes = context.read<EngineController>().remotes;
    await tasks.load();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TaskController controller = context.watch<TaskController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasksTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.tasksTriggers,
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TriggersPage()),
              ),
            ),
            icon: const Icon(Icons.schedule),
          ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: controller.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(controller),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_createTask()),
        icon: const Icon(Icons.add),
        label: Text(l10n.tasksNew),
      ),
    );
  }

  Future<void> _createTask() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => const TaskEditPage()),
    );
    if (mounted) await _refresh();
  }

  Future<void> _editTask(SyncTask task) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => TaskEditPage(existing: task)),
    );
    if (mounted) await _refresh();
  }

  Widget _buildBody(TaskController controller) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (controller.isLoading && controller.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.tasks.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
        children: <Widget>[
          Icon(
            Icons.sync_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.tasksEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tasksEmptyHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: controller.tasks.length,
      itemBuilder: (BuildContext context, int index) {
        final SyncTask task = controller.tasks[index];
        final TaskRunState state = controller.stateOf(task.id);
        return _TaskTile(
          task: task,
          state: state,
          onRun: state.running
              ? null
              : () => unawaited(controller.runTask(task)),
          onCancel: state.running ? controller.cancelRunning : null,
          onEdit: () => unawaited(_editTask(task)),
          onDelete: () => unawaited(_confirmDelete(controller, task)),
          onToggleWifiOnly: () => unawaited(
            controller.saveTask(task.copyWith(wifiOnly: !task.wifiOnly)),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(TaskController controller, SyncTask task) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.tasksDeleteTitle(task.title)),
        content: Text(l10n.tasksDeleteBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) await controller.deleteTask(task.id);
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.state,
    required this.onRun,
    required this.onCancel,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleWifiOnly,
  });

  final SyncTask task;
  final TaskRunState state;
  final VoidCallback? onRun;
  final VoidCallback? onCancel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleWifiOnly;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    task.title.isEmpty ? l10n.tasksUntitled : task.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.wifiOnly)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.wifi, size: 16, color: scheme.primary),
                  ),
                IconButton(
                  tooltip: state.running ? l10n.transferCancel : l10n.tasksSyncNow,
                  icon: state.running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  onPressed: state.running ? onCancel : onRun,
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.commonMore,
                  onSelected: (String action) {
                    switch (action) {
                      case 'edit':
                        onEdit();
                      case 'wifi':
                        onToggleWifiOnly();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.tune),
                        title: Text(l10n.tasksEdit),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'wifi',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.wifi),
                        title: Text(
                          task.wifiOnly
                              ? l10n.tasksWifiOnlyOff
                              : l10n.tasksWifiOnlyOn,
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_outline),
                        title: Text(l10n.commonDelete),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              task.direction.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              task.pathSummary,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (state.running) ...<Widget>[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: state.progress.hasTotal ? state.progress.ratio : null,
              ),
              const SizedBox(height: 4),
              Text(
                '${state.progress.humanReadableBytes} / '
                '${state.progress.humanReadableTotal}   '
                '${state.progress.humanReadableSpeed}   '
                'ETA ${state.progress.humanReadableEta}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (state.lastError != null) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.lastError!,
                      style: TextStyle(color: scheme.error, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (state.succeeded) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(Icons.check_circle_outline,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    l10n.tasksLastSync(_format(state.lastFinishedAt!)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _format(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
