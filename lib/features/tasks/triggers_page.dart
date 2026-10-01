import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/controllers/task_controller.dart';
import '../../core/models/sync_task.dart';
import '../../core/models/trigger.dart';
import '../../core/services/trigger_scheduler.dart';

/// 触发器列表 —— 对应原生 `Fragments/TriggerFragment.java`。
class TriggersPage extends StatelessWidget {
  const TriggersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TaskController controller = context.watch<TaskController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.triggersTitle)),
      body: controller.triggers.isEmpty
          ? Center(child: Text(l10n.triggersEmpty))
          : ListView(
              children: controller.triggers
                  .map(
                    (Trigger trigger) => _TriggerTile(
                      trigger: trigger,
                      taskTitle: _taskTitle(controller, trigger.triggerTarget),
                      onToggle: (bool value) => unawaited(
                        controller
                            .saveTrigger(trigger.copyWith(isEnabled: value)),
                      ),
                      onTap: () => unawaited(
                        _edit(context, controller, trigger),
                      ),
                      onDelete: () => unawaited(
                        controller.deleteTrigger(trigger.id),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => unawaited(_edit(context, controller, null)),
        child: const Icon(Icons.add),
      ),
    );
  }

  static String _taskTitle(TaskController controller, int taskId) {
    for (final SyncTask task in controller.tasks) {
      if (task.id == taskId) return task.title;
    }
    return '（任务已删除）';
  }

  static Future<void> _edit(
    BuildContext context,
    TaskController controller,
    Trigger? existing,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => _TriggerEditPage(existing: existing)),
    );
    await controller.load();
  }
}

class _TriggerTile extends StatelessWidget {
  const _TriggerTile({
    required this.trigger,
    required this.taskTitle,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  final Trigger trigger;
  final String taskTitle;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      leading: Icon(
        trigger.type == TriggerType.interval
            ? Icons.timer_outlined
            : Icons.schedule,
      ),
      title: Text(
        trigger.title.isEmpty ? l10n.triggersUntitled : trigger.title,
      ),
      subtitle: Text('${TriggerScheduler.describe(trigger)}\n→ $taskTitle'),
      isThreeLine: true,
      trailing: IconButton(
        icon: Icon(trigger.isEnabled ? Icons.toggle_on : Icons.toggle_off),
        color: trigger.isEnabled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
        onPressed: () => onToggle(!trigger.isEnabled),
      ),
      onTap: onTap,
      onLongPress: onDelete,
    );
  }
}

class _TriggerEditPage extends StatefulWidget {
  const _TriggerEditPage({this.existing});

  final Trigger? existing;

  @override
  State<_TriggerEditPage> createState() => _TriggerEditPageState();
}

class _TriggerEditPageState extends State<_TriggerEditPage> {
  /// 便捷取用本地化文案。
  AppLocalizations get l10n => AppLocalizations.of(context);

  static const List<int> _intervalPresets = <int>[15, 30, 60, 120, 360, 720];

  late final TextEditingController _title;
  late TriggerType _type;
  late int _weekdayMask;
  late TimeOfDay _time;
  late int _intervalMinutes;
  int _target = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Trigger? existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _type = existing?.type ?? TriggerType.schedule;
    _weekdayMask = existing?.weekdayMask ?? Trigger.defaultWeekdayMask;
    _intervalMinutes = existing?.intervalMinutes ?? 60;
    _target = existing?.triggerTarget ?? 0;
    final int minutes = existing?.time ?? 0;
    _time = TimeOfDay(
      hour: existing == null ? 3 : (minutes ~/ 60) % 24,
      minute: existing == null ? 0 : minutes % 60,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_target == 0) {
      setState(() => _error = l10n.triggersErrorTarget);
      return;
    }
    setState(() => _error = null);

    final Trigger trigger = Trigger(
      id: widget.existing?.id ?? 0,
      title: _title.text.trim(),
      isEnabled: widget.existing?.isEnabled ?? true,
      weekdayMask: _weekdayMask,
      // `time` 的语义随类型变化：按时刻 = 距 00:00 的分钟；间隔 = 分钟数。
      // 原生 `TriggerActivity.kt:179` 就是这么存的。
      time: _type == TriggerType.schedule
          ? Trigger.timeFromClock(_time.hour, _time.minute)
          : _intervalMinutes,
      triggerTarget: _target,
      type: _type,
    );

    await context.read<TaskController>().saveTrigger(trigger);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final List<SyncTask> tasks = context.watch<TaskController>().tasks;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? l10n.triggersNew : l10n.triggersEdit,
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: l10n.filtersName,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _target == 0 ? null : _target,
            decoration: InputDecoration(
              labelText: l10n.triggersTarget,
              border: OutlineInputBorder(),
            ),
            items: tasks
                .map(
                  (SyncTask task) => DropdownMenuItem<int>(
                    value: task.id,
                    child: Text(
                      task.title.isEmpty
                          ? l10n.tasksUntitled
                          : task.title,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (int? value) => setState(() => _target = value ?? 0),
          ),
          const SizedBox(height: 16),
          SegmentedButton<TriggerType>(
            segments: TriggerType.values
                .map(
                  (TriggerType type) => ButtonSegment<TriggerType>(
                    value: type,
                    label: Text(type.label),
                  ),
                )
                .toList(growable: false),
            selected: <TriggerType>{_type},
            onSelectionChanged: (Set<TriggerType> value) =>
                setState(() => _type = value.first),
          ),
          const SizedBox(height: 16),
          if (_type == TriggerType.schedule) ...<Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(l10n.triggersTime),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(_pickTime()),
            ),
            const SizedBox(height: 8),
            Text(l10n.triggersDays,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List<Widget>.generate(7, (int index) {
                final bool selected = (_weekdayMask >> index) & 1 == 1;
                return FilterChip(
                  label: Text(Trigger.weekdayLabels[index]),
                  selected: selected,
                  onSelected: (bool value) => setState(() {
                    final int bit = 1 << index;
                    _weekdayMask = value
                        ? (_weekdayMask | bit)
                        : (_weekdayMask & ~bit);
                  }),
                );
              }),
            ),
          ] else ...<Widget>[
            Text(l10n.triggersInterval,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _intervalPresets
                  .map(
                    (int minutes) => ChoiceChip(
                      label: Text(
                        minutes < 60
                            ? l10n.intervalMinutes(minutes)
                            : l10n.intervalHours(minutes ~/ 60),
                      ),
                      selected: _intervalMinutes == minutes,
                      onSelected: (bool value) {
                        if (value) {
                          setState(() => _intervalMinutes = minutes);
                        }
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.triggersSystemLimits,
              style: TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => unawaited(_save()),
            icon: const Icon(Icons.check),
            label: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}
