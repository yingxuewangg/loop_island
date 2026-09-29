# 循环小岛 / Loop Island

> 无登录、无账号、本地优先的 **TodoList + N 天循环计划** 应用。
> 按「周期的第几天」而不是星期几来安排任务:`第 1 天 → 第 2 天 → … → 第 N 天 → 回到第 1 天`,循环往复。

![Flutter](https://img.shields.io/badge/Flutter-3.19+-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/平台-Android%20%7C%20Windows-4BC35F)

---

> ## ✨ 写在前面
>
> 这个项目由一位**编程小白**独立创建,从需求、设计到编码都是边学边做,难免会有不完美的地方 —— 欢迎提 Issue 和 PR,也欢迎 fork 出去改成你自己的样子。
>
> **为什么要做这个应用?** 市面上的 TodoList 大多只能记「某天要做的事」,最多支持「每周几重复」;但生活里很多事不是按星期走的 —— 比如一套 3 天的护肤流程、一份 7 天的训练课表、一个 14 天的打卡挑战。**大部分 TodoList 都不能自定义一个完整的周期去循环任务**,所以我构建了这个项目:你可以创建任意天数的周期计划,逐天定制任务和休息日,每天到点自动生成当天的任务并提醒你,一轮走完自动回到第 1 天,周而复始。

---

## 一、功能特性

| 模块 | 能做什么 |
| --- | --- |
| **普通任务** | 新建 / 编辑 / 勾选完成 / 跳过 / 标记未完成;日期支持今天、明天、自定义、无日期;同一天可设**多个提醒时段**(最多 5 个) |
| **循环计划** | 自定义 **N 天周期**(1~365 天),逐天定义任务与休息日;到点自动生成当天的任务;支持暂停 / 恢复 / 复制 / 删除;结束条件支持「永不结束」「循环 X 次」「到指定日期」 |
| **修改循环任务** | 「仅本次」只改当天实例、「以后所有」修改周期模板并重算未来实例 |
| **今日 / 明日** | 今日汇总普通任务与所有计划当天的实例,直接勾选;明日纯预览,不写数据 |
| **提醒** | 本地通知:普通任务按具体时刻提醒,循环计划按每日时段提醒;点通知回到「今日」页,由你自己决定状态 |
| **统计** | 今日进度、当前周期进度、连续打卡(当前 / 最长)、最近 90 天热力图、未完成记录清单 |
| **未完成原因** | 未完成 / 跳过的任务可以填原因,在统计页回看 |
| **数据管理** | 导出 JSON 备份、导入恢复(覆盖或合并)、清空业务数据 |

## 二、截图

| 页面 | 说明 | 图片 |
| --- | --- | --- |
| 今日 | 今日进度 + 普通任务与循环任务 + 明日预览 | `docs/screenshots/android-today.png` |
| 任务 | 按 今天 / 明天 / 已完成 分组的任务列表 | `docs/screenshots/android-tasks.png` |
| 计划 | 循环计划列表(进行中 / 已归档) | `docs/screenshots/android-cycles.png` |
| 计划详情 | 第 1~N 天与每天的任务预览 | `docs/screenshots/android-cycle-detail.png` |
| 新建任务 | 日期、多时段提醒与状态 | `docs/screenshots/android-new-task.png` |
| 设置 | 提醒设置、统计、数据管理入口 | `docs/screenshots/android-settings.png` |

## 三、下载安装

到 [**Releases**](../../releases) 页面下载 APK:

| 文件 | 适合谁 |
| --- | --- |
| `loop_island-<版本>-arm64-v8a.apk` | **现代手机装这个**(2016 年以后的绝大多数手机) |
| `loop_island-<版本>-armeabi-v7a.apk` | 很老的老设备 |
| `loop_island-<版本>-x86_64.apk` | 模拟器 / x86 平板 |
| `loop_island-<版本>-universal.apk` | 不确定就装这个(体积最大,通吃) |

Windows 桌面版可自行从源码构建(见下节)。

## 四、从源码运行

```bash
git clone https://github.com/yingxuewangg/loop_island.git
cd loop_island
flutter pub get

# Windows 桌面(需要 Visual Studio 的「使用 C++ 的桌面开发」工作负载)
flutter run -d windows

# Android 真机 / 模拟器
flutter devices            # 找到设备 id
flutter run -d <device-id>
```

## 五、数据与隐私

- **没有登录、没有账号、没有服务器,没有统计上报,不含任何第三方分析 SDK,应用代码不发起任何网络请求。**
- 所有数据只保存在本机一个文件里,不会上传云端:
  - Android:`/data/user/0/loop_island.yxw/app_flutter/loop_island_data.hive`
  - Windows:`%USERPROFILE%\Documents\loop_island_data.hive`
  - 准确路径可在应用内 **设置 → 关于与隐私 → 数据存储位置** 查看
- 存储采用「单键 + 原子快照」:全部数据序列化成一份 JSON 整体写入,写入失败会回滚内存状态并把错误抛给界面,不会出现「看着保存成功、其实没存下来」。
- **导出 / 导入**:设置 → 数据管理,导出一份带版本号的 JSON 备份;导入前先预览,支持「覆盖」与「合并」(同一条取较新者胜,设置保留本地)。备份里包含任务、计划、记录与未完成原因,请自行妥善保管。

## 六、技术栈与项目结构

- **Flutter**(Android + Windows 桌面),状态管理用 **Riverpod**,本地存储用 **Hive**
- 分层:`features/`(界面) → `app/`(外壳与主题) → `data/`(存储与命令层) → `models/` → `core/`(纯 Dart 计算引擎) → `services/`(通知、文件 IO)
- 纯计算(循环实例化、日期、统计、备份编解码)全部收在 `core/`,可脱离 Flutter 做纯 Dart 单测

详细的分层规则、依赖方向与数据流见 **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**,需求背景见 **[docs/PRD.md](docs/PRD.md)**。

## 七、参与开发

```bash
flutter analyze    # 静态检查,期望 No issues found!
flutter test       # 单元 + widget 测试,期望全部通过
```

提交前请保证两条命令全绿。欢迎提 Issue 描述你遇到的问题或想要的功能。

## 八、许可证

本项目基于 [MIT License](LICENSE) 开源。
界面组件库 [animal_island_flutter](https://pub.dev/packages/animal_island_flutter) 同样采用 MIT 许可。
