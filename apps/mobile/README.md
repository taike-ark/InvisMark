# 隐迹 InvisMark · 移动端（Flutter）

液态玻璃 UI 脚手架，对应设计规范 [`docs/wmforge-移动端UI规范-液态玻璃.md`](../../docs/wmforge-移动端UI规范-液态玻璃.md)。

**零第三方依赖**：只用 Flutter SDK 自带能力 + `cupertino_icons`。
相册/相机/保存/分享等需要原生插件的能力全部用 `// TODO(M3)` 标注，等 M3 阶段接入。

- Flutter：`sdk: ^3.5.0`（建议 3.24+，Impeller 默认开启）
- 状态管理：`ChangeNotifier` + `InheritedNotifier`（不引 provider/riverpod）
- 网络：`dart:io HttpClient`（不引 dio/http）

---

## 1. 目录结构

```
apps/mobile/
├─ pubspec.yaml
├─ analysis_options.yaml
├─ lib/
│  ├─ main.dart                     # runApp + MaterialApp（亮/暗主题、标题「隐迹 InvisMark」）
│  ├─ app.dart                      # IndexedStack 三页 + 悬浮玻璃 TabBar + 档位解析
│  ├─ theme/
│  │  ├─ tokens.dart                # 唯一 Token 源：颜色/圆角/间距/字阶/动效/玻璃材质/档位
│  │  └─ app_theme.dart             # ThemeData 亮/暗
│  ├─ widgets/
│  │  ├─ glass_container.dart       # 液态玻璃核心 + AdaptiveGlassScope + 三档材质
│  │  ├─ glass_button.dart          # 主按钮（实色渐变，不用玻璃）/ 次按钮（玻璃胶囊）
│  │  ├─ glass_card.dart            # 玻璃卡片
│  │  └─ risk_banner.dart           # 分享渠道风险条 + 风险 sheet
│  ├─ screens/
│  │  ├─ home_screen.dart           # 最近任务 + 大按钮「选图嵌入」
│  │  ├─ result_screen.dart         # PSNR/SSIM、trace_id、保存/分享/复制链接
│  │  ├─ detect_screen.dart         # 选图检测：命中 / 未检出两态
│  │  └─ settings_screen.dart       # API 地址、玻璃档位、外观、隐私说明
│  ├─ services/api_client.dart      # POST /v1/embed、/v1/extract（手写 multipart）
│  ├─ models/trace.dart             # EmbedResult / TraceResult / EmbedQuality
│  └─ state/app_state.dart          # AppState(ChangeNotifier) + AppStateScope
└─ test/widget_test.dart            # 冒烟测试：pump 首页，断言标题
```

---

## 2. 补齐平台目录（首次）

本仓库只提交了 Dart 源码，`android/`、`ios/`、`web/` 等平台目录由 `flutter create` 生成：

```bash
cd apps/mobile
flutter create --project-name invismark_mobile --org com.invismark \
  --platforms=android,ios .
```

> `flutter create` 只补齐缺失的平台目录；如果它改写了 `lib/main.dart`，用 `git checkout -- lib/main.dart` 恢复即可。
> 它同时会生成 `.gitignore`（含 `build/`、`.dart_tool/` 等忽略项），提交前确认这些生成物没被纳入版本库。

然后：

```bash
flutter pub get
flutter run          # Android 模拟器 / 真机
flutter analyze      # 应为 0 error
flutter test         # 冒烟测试
```

Android 建议在 `android/app/src/main/AndroidManifest.xml` 中确认 `INTERNET` 权限（模拟器访问宿主机需 `http://10.0.2.2:8000` 明文 HTTP，Android 9+ 需要 `usesCleartextTraffic="true"` 或仅开发期用 `network_security_config` 放行）。

---

## 3. 配置 API 地址

优先级：设置页输入 > `AppState.defaultBaseUrl`（`lib/state/app_state.dart`）。

| 场景 | 地址 |
|---|---|
| Android 模拟器访问宿主机 | `http://10.0.2.2:8000` |
| 真机 / 局域网 | `http://192.168.x.x:8000` |
| 线上 | `https://api.example.com` |

- 缺 `http://` 会自动补全；非法地址在设置页会提示。
- 地址变更会销毁重建 `ApiClient`（连接池与地址绑定），见 `AppState.applyBaseUrl`。
- 鉴权：`ApiClient(authToken: ...)` 会带 `Authorization: Bearer <token>`；设备绑定流程待 M3。
- 当前地址只存在内存，**重启丢配置**（M3 决定 shared_preferences 还是写 profile 目录文件）。

接口契约见《项目说明书》§8：`POST /v1/embed`（multipart: `file`, `resource_code?`, `strength?`）、`POST /v1/extract`（multipart: `file`）。
超时：连接 10s / 请求 60s；失败按 `400ms → 800ms` 指数退避重试（默认 2 次，4xx 不重试）。

---

## 4. 三档降级（Full / Lite / Opaque）

规范 §7.2 的三档在这里实现：

| 位置 | 作用 |
|---|---|
| `lib/theme/tokens.dart` → `enum GlassTier` / `enum GlassPreference` / `class GlassMaterialSpec` / `chooseGlassTier()` | 档位定义、每档材质参数（blurFull=24 / blurLite=12 / opaque=0）、纯函数解析逻辑 |
| `lib/widgets/glass_container.dart` → `AdaptiveGlassScope` | 把当前档位下发给所有玻璃；`GlassContainer` 默认读取，也可用 `tier:` 显式覆盖 |
| `lib/app.dart` → `_AppShellState.build` | 汇总偏好 + 系统高对比（近似「降低透明度」）→ `resolveTier()` → 传给 Scope；冷启动首帧强制 `opaque` 200ms |
| `lib/state/app_state.dart` → `AppState.resolveTier()` / `glassPreference` | 用户设置项「视觉效果：自动/完整/精简/关闭」 |

行为差异：

- **full**：`BackdropFilter(blur 24)` + 左上镜面高光 + 右下环境光 + 按压高光扫过动画。
- **lite**：`BackdropFilter(blur 12)`，`animatesHighlight = false`（不做实时高光动画，只保留静态高光）。
- **opaque**：**完全不创建 `BackdropFilter`**（`usesBackdropFilter = false`），改画不透明渐变底 + 极淡白色叠加，圆角/描边/投影都保留，视觉不塌。

`chooseGlassTier(preference, reduceTransparency, powerSaver, grade, measuredFps)` 是纯函数，可直接单测：
自动档在「降低透明度 / 省电」时直接 Opaque，设备分级 `low` 或采样帧率 < 50fps 时 Lite，否则 Full。

---

## 5. 液态玻璃实现要点

`GlassContainer` 的层叠（对应规范 §2 五层）：

```
RepaintBoundary                      ← 隔离重绘
 └ BoxShadow(0 12 32)                ← Z4 投影（在裁剪之外）
    └ ClipRRect(radius)              ← 圆角来自 AppRadius
       └ BackdropFilter(blur)        ← 仅 full/lite；opaque 档不创建
          └ Stack
             ├ CustomPaint           ← Z1 双 overlay 基体 + 镜面高光 + Z2 1px 内描边（顶部更亮）
             └ content               ← Z3 内容
```

- 按压：`scale 0.97`（胶囊 0.98）+ 高光扫过，`spring(0.34,1.2)` 用 `Cubic(0.34, 1.2, 0.64, 1.0)` 近似；Reduce Motion 下退化为直接切换。
- 所有颜色/圆角/模糊半径/时长/尺寸都来自 `tokens.dart`，页面里没有字面色值与魔法数字。
- 每块玻璃外包 `RepaintBoundary` 隔离重绘；滚动列表里不放玻璃。

### 玻璃预算与图片区零玻璃

- 每屏玻璃 ≤ 3（`AppLayout.maxGlassPerScreen`，含 TabBar）。各屏的预算分配写在对应文件顶部注释里。
- 图片本体区域**禁止**任何玻璃/模糊层：`_RecentImageArea`（首页）、`_Viewfinder`（检测页）、`_ImageViewer`（结果页）里都有显式注释。
- 玻璃内部不再叠玻璃按钮：卡内动作用扁平按钮（`_FlatButton`），主 CTA 用实色渐变 `GlassPrimaryButton`。

---

## 6. TODO：M3 原生能力接入点

全仓搜索 `TODO(M3)` 即可定位：

| 能力 | 位置 | 说明 |
|---|---|---|
| 相册/相机选图 | `home_screen.dart` `_PickerSheet`、`detect_screen.dart` `_pickAndDetect` | `image_picker` / `camera`，拿到 bytes 后调用 `AppState.embedImage()` / `detectImage()` |
| 保存到相册 | `result_screen.dart` `_saveToGallery` | Android MediaStore / iOS PHPhotoLibrary |
| 分享 | `result_screen.dart` `_share` | `share_plus`，先过风险 sheet |
| 证据包 | `result_screen.dart` `_openProof`、`detect_screen.dart` `_openProof` | `url_launcher` 打开 `report_url` |
| 配额 | `home_screen.dart` `quotaUsed/quotaLimit` | `GET /v1/quota` |
| 省电模式 | `app.dart`、`settings_screen.dart` | `battery_plus` 或平台通道 |
| 焦点折射 shader | `glass_container.dart` `_GlassSurfacePainter` | `FragmentProgram` + `saturate 1.8`（当前只有 2px 焦点边缘光） |
| 设置持久化 | `app_state.dart` | shared_preferences / 文件 |
| 帧率采样自动降级 | `app_state.dart` `resolveTier(measuredFps:)` 参数位 | `SchedulerBinding.addTimingsCallback` 采样 200ms 均值 |

当前无原生插件时，UI 用「演示数据」走通：首页选图弹窗 / 检测页「演示：命中」「演示：未检出」。

---

## 7. 与规范的偏差（有意为之）

1. `GlassPill` 高度取 **44**（规范 §5 写 H40）：§8 要求触控目标 ≥ 44，取 44 兜住两条。
2. TabBar 标签用 **13pt**（§3.3 建议 caption 11pt）：与「玻璃上禁止 < 13pt」冲突，取可读性优先。
3. `GlassSheet` 用四角 `radius-xl` 的浮动面板，而非仅上圆角贴底：脚手架阶段追求简单一致，M3 再按 §5 做贴底抽屉。
4. 投影强度按 §3.5（亮 0.12 / 暗 0.40），§2/§12 的 0.28/0.45 未采用（两处规范互相冲突，以 §3.5 双模式表为准）。
5. `saturate(180%)` 与焦点折射 shader 未实现：Flutter 无内置饱和滤镜，需 M3 的 `FragmentProgram`；当前 `GlassMaterialSpec.saturation` 只作为参数占位。
6. 字体：MiSans / Inter 需以 assets 接入，当前用 `fontFamilyFallback` 走系统字体兜底。

---

## 8. 验证状态

编写环境**没有 Flutter / Dart SDK，也没有网络**，因此以下结论来自静态自检脚本（不是编译器）：

| 检查项 | 结果 |
|---|---|
| 文件清单 | 19 个文件（16 个 `.dart` + pubspec + analysis_options + README） |
| 全部文件 UTF-8 合法、无 BOM、YAML 无 tab 缩进 | ✅ |
| `pubspec.yaml` YAML 结构（自有极简解析器，环境无 pyyaml） | ✅ name/env/deps 与要求一致 |
| `analysis_options.yaml` 结构 | ✅ include flutter_lints + strict 模式 |
| Dart 词法级括号配平（去掉注释/字符串后计数，保留 `${}` 内代码） | ✅ 16/16 |
| 所有 `App*.xxx` Token 引用都在 `tokens.dart` 中定义 | ✅ |
| `palette.*` 字段都存在；`AppPalette` 26 个 required 参数在亮/暗实例中齐全 | ✅ |
| 相对 import 目标存在 | ✅ |
| 零第三方 package（仅 flutter / flutter_test / invismark_mobile） | ✅ |
| 每个 `.dart` 首行 SPDX 头 | ✅ |
| 无 `build/`、`.dart_tool/`、`.flutter-plugins*` 生成物 | ✅ |

⚠️ **未验证的部分**（需要装 SDK 后补）：

- `flutter analyze`（unused import / const 建议 / 类型错误等编译器级检查）
- `flutter test`（`test/widget_test.dart` 只做过逻辑审读，未实际运行）
- `flutter run` 真机/模拟器渲染效果（玻璃模糊、档位切换、布局是否溢出）
- 与真实后端的联调（`/v1/embed`、`/v1/extract` 的字段与错误码）

装好 SDK 后按第 2 节补齐平台目录，再依次执行 `flutter pub get` → `flutter analyze` → `flutter test` → `flutter run`。
