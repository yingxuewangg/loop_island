# 循环小岛 / Loop Island — 架构说明

> 本文档定义代码分层、依赖方向与命名约定。**任何新增文件都必须落在此框架内。**

---

## 1. 分层与依赖方向

依赖只能**自上而下**，绝不允许反向或跨层回环：

```
features/  (UI 页面与组件)
    ↓  只读 provider / 调命令层
app/       (应用外壳：主题、路由、Tab、文案常量)
    ↓
data/      (存储实现、仓库、命令层、Riverpod providers)
    ↓
models/    (纯数据模型：Task / Cycle / CycleDay / Record / Settings / Backup)
    ↓
core/      (纯 Dart 计算引擎：日期、周期实例化、统计、导入导出编解码)
    ↓
services/  (平台能力封装：通知、应用锁、文件 IO) —— 只被 data/app 调用
```

> **唯一被允许的「向上」引用**：`services/` 可以 import `app/l10n_strings.dart`。
> 那个文件是**纯文案常量库**（只依赖 `core/`，不含任何 Flutter 组件、也从不 import
> `services/`），把它当成和 `core/` 同一层的常量表即可。反过来 `app/l10n_strings.dart`
> 永远不许 import `services/`、`data/`、`features/`，否则就真的成环了。

### 各层职责

| 目录 | 职责 | 硬性约束 |
| --- | --- | --- |
| `lib/core/` | 纯业务计算：日期工具、周期引擎、统计、任务分组、快捷原因、备份编解码 | **禁止 import `package:flutter/*`**；只允许 `dart:*` 与 `models/`；必须可被纯 Dart 单测覆盖 |
| `lib/models/` | 数据模型 + JSON 序列化/容错解析 + 枚举 | 不依赖 `core/`、`data/`、UI；`fromJson` 对脏数据必须返回默认值而不是抛异常 |
| `lib/data/` | `LocalStore` 抽象与实现（Hive / 内存）、`AppRepository` 快照、命令层（task/cycle/record commands）、Riverpod providers | 命令层是**唯一**的写入口；UI 不得直接改模型集合 |
| `lib/services/` | 平台能力封装：本地通知、调度、应用锁、文件导入导出 IO | 不支持的平台必须降级为 no-op，不得抛异常；对外暴露接口以便 fake 测试 |
| `lib/features/` | 页面与页面级组件，按业务域分子目录 | 不直接读写 `LocalStore`；不实现业务规则（规则放 `core/`） |
| `lib/app/` | `LoopIslandApp`（主题 + 本地化）、`AppShell`（4 Tab）、路由表、中文文案常量 | 唯一持有 `MaterialApp` 的地方 |

### features 子目录与 PRD 页面的对应

| 目录 | 对应页面 |
| --- | --- |
| `features/today/` | Tab 1 今日（含明日预览卡片） |
| `features/tasks/` | Tab 2 任务列表、任务编辑页 |
| `features/cycle/` | Tab 3 计划列表、计划详情、计划编辑、某一天编辑 |
| `features/stats/` | 统计页、热力图 |
| `features/day/` | 某天详情页 |
| `features/reason/` | 未完成原因弹窗与展示组件 |
| `features/settings/` | Tab 4 设置、提醒设置、导出、导入、数据管理、关于 |

---

## 2. 命名约定

| 类型 | 约定 | 示例 |
| --- | --- | --- |
| 模型 | 名词单数，`toJson` / `fromJson` / `copyWith` 三件套 | `Task`、`Cycle`、`Record` |
| 纯计算函数 | 动词短语，置于 `core/`，无副作用 | `cycleDayIndexAt()`、`todayProgress()` |
| 命令层 | `xxx_commands.dart`，方法名动词开头 | `task_commands.dart` → `addTask()` |
| Riverpod provider | 名词 + `Provider` 后缀 | `todayViewProvider`、`appDataProvider` |
| 页面 | `xxx_page.dart` | `task_edit_page.dart` |
| 页面级组件 | `widgets/xxx.dart` | `widgets/task_tile.dart` |
| 测试 | 与被测文件同名 + `_test.dart` | `test/core/cycle_engine_test.dart` |
| 测试假数据 | 集中在 `test/support/factories.dart` | `makeTask()`、`makeCycle()` |

---

## 3. 数据流

```
用户操作 (features/)
   → 命令层 (data/xxx_commands.dart)
      → AppRepository._commit(AppData next)     // 内存快照不可变替换
         → LocalStore.save(AppBackup)           // 异步持久化
            → Riverpod provider 失效 → UI 重建
```

- `AppData` 是**不可变**快照，所有改动都产生新实例，便于比较与测试。
- 时间统一走 `core/date_x.dart`，存储用 `yyyy-MM-dd` 字符串（`dayKey`），避免时区漂移。
- 导入导出统一走 `core/backup_codec.dart`，本地存储与 JSON 备份共用同一套 `toJson/fromJson`，保证「导出 → 清空 → 导入」后数据等价。

### 提醒（通知）的数据流

```
数据变化（每日维护 / 勾选 / 编辑 / 改设置）
  → AppShell（提醒同步的唯一 owner）
     → ReminderScheduler.sync(data, settings, now)
        → buildReminders(...)         // 纯函数：算出「此刻该有哪些提醒」
        → 与上次的 ScheduledReminder 集合做差分
           → NotificationService.scheduleOnce / cancel / cancelAll
              → NotificationBackend（真实实现 = flutter_local_notifications）
```

- **`AppShell` 是提醒同步的唯一 owner**，和每日维护一样。设置页只负责把开关写进
  `AppSettings`，**不自己调调度器** —— 否则又会出现「多个页面各同步一次」的老问题。
  同步是**差分 + 幂等**的，且会循环收敛（同步期间来了新快照就按新快照再算一次）。
- **通知 ID 必须跨进程稳定**：`notificationIdFor(key)` 是手写的 FNV-1a，不能用
  `String.hashCode`（Dart 的字符串哈希不同进程不一致，会让「改提醒」变成「多一条旧提醒」）。
  任务 ID 里带**具体时刻**、计划 ID 里带**日期 + 时刻**（`taskReminderId` / `cycleReminderId`）：
  一个对象可以有多个提醒时段，ID 必须能区分它们；时刻没变 ID 就不变，改时刻等于换一条通知。
- **多时段（一天提醒 N 次）的规则只写一份**：夹取、去重、升序、截断到
  `kMaxRemindSlots` 全部收在 `core/remind_slots.dart`，模型反序列化、命令层、界面三者共用。
  三个模型的字段都是列表（`Task.remindAts` / `Cycle.remindMinutesOfDay` /
  `AppSettings.defaultRemindMinutesOfDay`），并各自保留「取最早一个」的单值 getter 给排序与
  单行展示用；`fromJson` 会把老备份里的单值键包成单元素列表，**不需要迁移脚本**。
- **循环提醒按天展开成一次性通知**（不是平台的「每日重复」）：正文要含
  「今天是第 x/N 天」，且结束日次日必须停止，重复通知两个都做不到。代价是滚动维护
  一个天数窗口，条数预算 50 条（iOS 待发送通知上限 64），窗口长度由
  `cycleReminderHorizon(每天条数)` 反推 —— **时段越多窗口越短**，总条数永远不越界。
  **已知限制**：连续超过窗口天数不打开应用，循环提醒会停 —— 这与「每日维护也要打开
  应用才会物化今天的实例」是同一个前提。
- `flutter_local_notifications` **只在 `local_notification_service.dart` 里出现**；
  其它地方一律依赖 `NotificationService` / `NotificationBackend` 抽象。


---

## 5. 已知命名隐患

- **`Record` 与 Dart 3 内置类型同名**：`lib/models/record.dart` 里的 `Record` 与语言内置的
  `Record` 类型重名。凡是用到该模型的文件**必须显式 `import`**，否则 `Record`
  会被解析成内置类型，报出一堆「`hasReason` isn't defined」之类看似莫名其妙的错误。
  已在使用处加注释；若将来觉得麻烦，可整体改名为 `TaskRecord`。

---

## 6. 验证约定

每个任务收尾必须执行：

```powershell
flutter analyze      # 期望：No issues found!
flutter test         # 期望：All tests passed!
```

### widget 测试的两条硬规矩

1. **必须用 `test/support/pump_app.dart` 的 `pumpLoopIslandApp` / `pumpWithScope` 挂载**，
   不要自己写 `pumpWidget(ProviderScope(...))`：前者会注入 `InMemoryLocalStore`、
   固定并归一 `todayProvider`、**默认注入 `NoopNotificationService`**，避免误写真实磁盘、
   随日期漂移的断言，以及每个用例都去初始化时区库 + 打平台通道。
   确实需要手动 `ProviderScope` 时（比如注入故障 store），必须自己补上
   `notificationServiceProvider` 的覆写。
2. **断言某个 Tab 的内容前必须先切到那个 Tab**：`AppShell` 用
   `IndexedStack` + `Visibility.maintain` 承载四个 Tab，非当前 Tab 处于 offstage，
   而 finder 默认 `skipOffstage: true` 会跳过它们。长页面还要先把测试视口调大
   （默认 800×600 之外的部分根本不会被构建）。
3. **要断言调度/取消行为时注入 `test/support/fake_notification_service.dart`**，
   它记录了 `onceCalls` / `dailyCalls` / `cancelled` / `cancelAllCount` 与
   `liveIds`（当前仍注册着的通知）。`AnimalSelect` 的下拉最多 260 高，
   要选靠后的选项（例如「22 时」）得先 `tester.ensureVisible(...)` 再 tap。
4. **不要用 `tester.pageBack()` 返回上一页**：它按 tooltip `Back` 找返回按钮，
   而本应用锁定了 `zh_CN`，Material 的返回按钮 tooltip 是「返回」，
   于是它找不到并回落到 Cupertino 的返回键而报错。用
   `tester.tap(find.byType(BackButton).last)`。
5. **页面压在主壳之上时，主壳（含底部导航栏）会变成 offstage**：
   要读它的状态得用 `find.byType(X, skipOffstage: false)`。

### 文本编辑约定

- **含非 ASCII 的文件只能用 `edit` / `write` 工具修改**，不要用 PowerShell
  `Set-Content` 做文本替换 —— 它会把 UTF-8 中文写成乱码。

### 平台构建约定

- `flutter_local_notifications` 要求 Android 开启 core library desugaring：
  `android/app/build.gradle.kts` 里的 `isCoreLibraryDesugaringEnabled = true` 与
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` **不能删**。
- `android/gradle.properties` 里的 `kotlin.incremental=false` **不能删**：
  pub 缓存（`C:`）与工程目录（`F:`）不在同一个盘时，Kotlin 增量编译缓存会抛
  `this and base files have different roots` 而让构建失败。
- `android/build.gradle.kts` 顶部那段「把子项目 compileSdk 抬到 36」的 `subprojects`
  块 **必须放在 `evaluationDependsOn(":app")` 之前**（那一句会立刻触发插件子项目求值，
  之后再注册 `afterEvaluate` 会报 `project is already evaluated`）。它存在的理由是
  `file_picker 8.x` 把 `compileSdk` 写死在 34，而 Flutter 默认已经是 36；
  file_picker 升级后可以删掉。
- **图标**：源图 `assets/icon/app_icon.png`（1024×1024），用
  `dart run flutter_launcher_icons` 生成五档 `mipmap-*/ic_launcher.png`、
  自适应图标（`mipmap-anydpi-v26/ic_launcher.xml`，背景铺整张图、前景透明）与
  Windows `windows/runner/resources/app_icon.ico`。改图标只需换源图再跑一次。
- **通知小图标**：`res/drawable-*/ic_stat_loop.png` 必须是**白色剪影 + 透明底**
  （系统只取 alpha 通道着色，塞彩色图会渲染成白方块）。
  更关键的是它**只能按名字在运行时查找**，资源压缩器看不到这种引用，
  release 构建会把它当无用资源删掉 —— 所以 `res/raw/keep.xml` 里的
  `tools:keep="@drawable/ic_stat_loop"` **不能删**，删了 release 包通知就没图标，
  而且**构建不会报任何错**（debug 包还是好的，最容易漏测）。
  凡是「运行时按名字取资源」的东西都要加进这个文件。
- **发布签名**：`android/key.properties`（不入库）→ `android/app/build.gradle.kts`
  里读成 `signingConfigs["release"]`；读不到就退回 debug 签名，保证别人 clone 能构建。
  **密钥丢了无法覆盖升级**，备份说明在 `android/keystore/签名与口令-请离线备份.txt`。
- Windows 构建需要 `$env:NUGET_EXE="$env:USERPROFILE\.nuget\nuget.exe"`
  （Flutter 自带的 NuGet 下载在本机会卡死）。

---

## 7. 组件库使用备忘

`reference/animal_island_flutter/skills/.../references/api.md` **与实际源码有出入**，
写代码前请以源码为准。已确认的坑：

| 组件 | api.md 的说法 | 实际源码 |
| --- | --- | --- |
| `AnimalSelectOption` | `value:` / `label: Widget` | `key: T` / `label: String` |
| `AnimalCheckbox` | 无单独勾选框；是**多选组**（`List<T> value`）。当作单勾选框用时传单元素选项 + 空 label |
| `AnimalBottomBar` | `AnimalBottomBarItem` 的选中态由组件内部着色（图标走 `IconTheme.merge`、文字走 `DefaultTextStyle.merge`），**不要自己传 color**，否则会盖掉选中效果 |
| `AnimalConfirmDialog` | 位于 `overlay.dart`（不在 `dialog.dart`），签名 `show({context, content, title, okText, cancelText, onOk, danger})` → `Future<bool?>` |
| `AnimalTimeline` | `AnimalTimelineItem({title, description, time, status, icon, onTap, disabled})` |

