import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/controllers/engine_controller.dart';
import 'core/controllers/settings_controller.dart';
import 'core/controllers/task_controller.dart';
import 'features/remotes/remotes_page.dart';
import 'features/settings/settings_page.dart';
import 'features/tasks/tasks_page.dart';
import 'theme/app_theme.dart';

/// 底部导航当前选中的页签。
///
/// 单独抽成 [ValueNotifier] 是为了让「应用快捷方式」等外部入口
/// （`quick_actions` 回调、系统分享）能够切换页签。
final ValueNotifier<int> homeTabNotifier = ValueNotifier<int>(0);

/// 系统分享进来的待处理文件路径。
///
/// `main()` 收到原生推送后写入这里，[RemotesPage] 订阅并弹出目标选择。
final ValueNotifier<List<String>?> shareIntakeNotifier =
    ValueNotifier<List<String>?>(null);

/// LeoSync 应用根组件。
class LeoSyncApp extends StatelessWidget {
  const LeoSyncApp({
    required this.engineController,
    required this.taskController,
    required this.settingsController,
    super.key,
  });

  final EngineController engineController;
  final TaskController taskController;
  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<EngineController>.value(
          value: engineController,
        ),
        ChangeNotifierProvider<TaskController>.value(value: taskController),
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (BuildContext context, SettingsController settings, _) {
          return DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              return MaterialApp(
                onGenerateTitle: (BuildContext context) =>
                    AppLocalizations.of(context).appTitle,
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(dynamicScheme: lightDynamic),
                darkTheme: AppTheme.dark(dynamicScheme: darkDynamic),
                themeMode: settings.themeMode,
                locale: settings.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const HomeShell(),
              );
            },
          );
        },
      ),
    );
  }
}

/// 底部导航壳。
///
/// 原生是 `MainActivity` + 抽屉导航（远端 / 任务 / 触发器 / 日志 / 设置…），
/// 这里收敛成三栏，其余页面从各自入口进入。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    homeTabNotifier.addListener(_onExternalTabRequest);
    _index = homeTabNotifier.value;
  }

  @override
  void dispose() {
    homeTabNotifier.removeListener(_onExternalTabRequest);
    super.dispose();
  }

  void _onExternalTabRequest() {
    if (!mounted) return;
    setState(() => _index = homeTabNotifier.value);
  }

  void _select(int value) {
    setState(() => _index = value);
    homeTabNotifier.value = value;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          RemotesPage(),
          TasksPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.cloud_outlined),
            selectedIcon: const Icon(Icons.cloud),
            label: l10n.tabRemotes,
          ),
          NavigationDestination(
            icon: const Icon(Icons.sync_outlined),
            selectedIcon: const Icon(Icons.sync),
            label: l10n.tabTasks,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.tabSettings,
          ),
        ],
      ),
    );
  }
}
