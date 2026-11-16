# 打包说明（复现 Windows EXE 与 Android APK）

本文件记录 **v0.1.0 两个可执行产物**怎么来的，以及踩过的坑，方便你在自己的机器/CI 上复现。
产物不打进版本库（`dist/` 已在 `.gitignore`），只随 Release 分发。

---

## 1. Windows EXE

**产物**：

| 文件 | 形态 | 说明 |
|---|---|---|
| `InvisMark-0.1.0-win64-gui.exe` | 单文件、窗口程序 | 桌面端（Tkinter），双击即用 |
| `InvisMark-0.1.0-win64-cli.exe` | 单文件、控制台 | 全部 CLI 子命令（embed/extract/batch/serve/gui/…） |
| `InvisMark-0.1.0-win64-portable.zip` | 两套 onedir 目录 | 启动更快，适合放 U 盘 |

**做法**：PyInstaller 6.x，只打包 numpy + tkinter，不含源码外的运行时。

```bash
pip install numpy pyinstaller
# 入口脚本：dist/entry_gui.py（调 invismark.desktop.app.main）
#           dist/entry_cli.py（调 invismark.cli.main）
python -m PyInstaller --onefile --windowed --name InvisMark ^
    --paths . --collect-submodules invismark dist/entry_gui.py
python -m PyInstaller --onefile --console  --name InvisMarkCLI ^
    --paths . --collect-submodules invismark dist/entry_cli.py
```

**踩过的坑**

1. **`typing` 反移植包冲突**：若环境里装了老的 `typing`（3.7.x 反移植），PyInstaller 会直接拒绝构建。
   处理：`pip uninstall typing`（3.11 自带 stdlib typing），或临时改名后再构建。
2. **单文件模式需要可写 `%TEMP%`**：PyInstaller `--onefile` 启动时先解压到 `%TEMP%`；
   受限账户/沙箱里 `%TEMP%` 不可写会报 `Could not create temporary directory`。
   这种环境请用 `--onedir`（portable zip）。
3. 体积：单文件 22.9 MB；onedir 两套合计 46 MB（压缩后）。numpy 占大头。
4. `--windowed` 的 GUI 版**没有控制台**，崩溃时看不到堆栈；调试请用 CLI 版 `invisMark gui` 复现。

---

## 2. Android APK

**产物**：`InvisMark-0.1.0-android.apk`（45.5 MB，通用 ABI，minSdk 24 / targetSdk 36）

- 包名：`com.invismark.invismark_mobile`
- 应用名：隐迹 InvisMark
- 签名：**Android Debug 证书**（Flutter 模板默认）。仅用于内测/自用，上架请换自己的 release keystore。

**做法**（Flutter 3.50 + Android SDK 36 + NDK 28.2.13676358 + JDK 21）：

```bash
# 1) 在 apps/mobile 的副本里补齐 Android 平台目录
flutter create --platforms=android --project-name invismark_mobile --org com.invismark .
flutter pub get

# 2) 构建
flutter build apk --release
#   → build/app/outputs/flutter-apk/app-release.apk
```

**踩过的坑**

1. **Flutter 3.50 强制要求 NDK 28.2.13676358**：即使 `android/app/build.gradle.kts` 里没写 `ndkVersion`，
   Flutter 的 Gradle 插件也会注入并校验。缺 NDK 会报
   `LicenceNotAcceptedException: ndk;28.2.13676358`。
   处理：`sdkmanager --licenses` 后 `sdkmanager "ndk;28.2.13676358"`。
2. **SDK 目录必须可写**：Gradle 要往 `$ANDROID_HOME/licenses` 补许可、装 NDK。
   如果 SDK 装在 `C:\Program Files`，请复制一份到用户目录，再用
   `flutter config --android-sdk <新路径>` 指过去（`local.properties` 里的 `sdk.dir` 会被 Flutter 覆盖）。
3. **Gradle wrapper 默认走 `services.gradle.org` → 跳 github.com**：网络受限时会报
   `PKIX path building failed`（其实是 github 被 hosts 指到了 127.0.0.1）。
   处理：把 `gradle-wrapper.properties` 的 `distributionUrl` 换成镜像或本地文件，例如
   `distributionUrl=file\:/F:/tools/gradle-dist/gradle-9.5.0-all.zip`；或
   `https://mirrors.cloud.tencent.com/gradle/gradle-9.5.0-all.zip`。
4. **Kotlin DSL 兼容**：Flutter 3.50 生成的 `app/build.gradle.kts` 里带
   `kotlin { compilerOptions { jvmTarget = … } }`，在 AGP 9 的 new DSL 下会报
   `Unresolved reference 'compilerOptions'`。
5. **⚠️ 启动即崩溃（`ClassNotFoundException: MainActivity`）**：
   模板的入口是 Kotlin 版 `MainActivity.kt`，但当前工具链（AGP 9.3.1 + `android.builtInKotlin=false`）
   **根本没有编译 Kotlin 源**（构建不报错，dex 里却缺入口类），APK 装上后一点就崩。
   修复：把入口改成 Java 版，`javac` 始终参与编译——
   ```java
   // android/app/src/main/java/com/invismark/invismark_mobile/MainActivity.java
   package com.invismark.invismark_mobile;
   import io.flutter.embedding.android.FlutterActivity;
   public class MainActivity extends FlutterActivity {}
   ```
   同时删掉 `app/build.gradle.kts` 里的 `kotlin { … }` 配置块与 `src/main/kotlin` 目录。
   自检方法：构建后确认 dex 里有入口类，别只看 "Built app-release.apk"：
   ```powershell
   # 解压 APK 后检查 classes.dex
   $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes('classes.dex'))
   $ascii.Contains('invismark_mobile/MainActivity')   # 必须是 True
   ```
   实机验证：`adb install -r` → `adb shell am start -n <pkg>/.MainActivity` → `adb shell pidof <pkg>` 有 pid 才算真跑起来。
6. **选图返回后 App 重启 / 闪退（vivo / 部分 ROM）**：
   `startActivityForResult` + `MethodChannel.Result` 的经典写法依赖 Activity 实例存活；
   部分 ROM（实测 vivo V1921A / Android 10，从相册返回时会重建 Activity，甚至重建 FlutterEngine）
   会让旧的 Result 回调失效——表现为「选完图 App 直接回到首页 / 闪退 / 卡住」。
   **修复**：选图结果不走 MethodChannel 回传，改成「原生侧落盘 → Dart 轮询取走」：
   - Java：`startPick()` 立即 `result.success(true)`；`onActivityResult` 把图片字节写进
     `cacheDir/picked/last.bin` + `last.name`；
   - Dart：`NativeMedia.pickImage()` 启动后每 400ms 调 `consumePendingPick()`，最多等 3 分钟。
   这样即使 Activity / Engine 被重建，图片也不会丢，App 也不会崩。
   同时在 `AndroidManifest.xml` 里关闭 Impeller，规避老 Adreno 驱动跨 Activity 返回时的崩溃：
   ```xml
   <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />
   ```
   排查心法：`adb logcat -s InvisMark` 看 `startPick / onActivityResult / pending pick stored` 三条日志，
   缺哪条就说明断在哪一步。
7. **vivo 安装要手点**：`adb install` 之后系统会弹「继续安装」，不点会一直卡住（`adb install` 不返回）。
   自动化脚本里要 `adb shell input tap` 那个按钮，或直接在手机上点。
8. **国内镜像**：`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、
   `PUB_HOSTED_URL=https://pub.flutter-io.cn`；Gradle 可用腾讯/阿里云镜像。
9. 构建机容器/沙箱里，`APPDATA`、`TEMP`、`GRADLE_USER_HOME`、`ANDROID_USER_HOME`
   都要指到可写目录，否则 Dart/Flutter 工具会因写 `.flutter_tool_state` 失败而退出。

---

## 3. 手机端「独立离线运行」是怎么做的

v0.1.0 起，App 默认**不依赖任何服务端**：水印引擎整体移植到了 Dart（`apps/mobile/lib/core/`）。

| 模块 | 文件 | 说明 |
|---|---|---|
| GF(256) / RS(64,24) | `core/gf256.dart`、`core/rs.dart` | BM + Chien + Forney，与 Python 版参数一致 |
| 24 字节追溯码 | `core/trace_codec.dart` | 与 Python 版字节布局、CRC32 完全一致，可互读 |
| PNG 编解码 | `core/png_codec.dart` | 纯 Dart + `dart:io` 的 zlib，零第三方依赖 |
| 水印引擎 | `core/watermark.dart` | 两级 DWT + 4×4 DCT + 归一化 AC 扩频 |
| 本地服务 | `services/local_engine.dart` | 解码图片（PNG 自研 / JPEG 走引擎）、独立 isolate 计算、seed/序号持久化 |

测试：`flutter test`（10 个用例：RS 纠错上限、追溯码 CRC、PNG 往返、嵌入→提取闭环、负样本、错误 seed）。

**跨端注意**：两端算法同构但随机数发生器不同（Python 用 numpy PCG64，Dart 用 splitmix64），
所以「同一 seed 的码图案」不互认；要跨端互解请统一用一侧实现，或把 seed/图案序列化后共用。

### 内置相册（不要用系统文件选择器）

实机（vivo V1921A / Android 10）验证时踩到一个坑：`ACTION_GET_CONTENT` 打开系统文件选择器后，
选完图回到 App 拿不到字节——轮询 3 分钟没有结果，表现为「选完图没反应」。
改为**内置相册**（`MainActivity` 里直接查 MediaStore）：

- `listImages(limit)`：按 `DATE_ADDED DESC` 列最近图片（首次请求 `READ_EXTERNAL_STORAGE` / `READ_MEDIA_IMAGES`）；
- `thumbnail(id, max)`：按需解码缩略图（`inSampleSize` + JPEG 82），列表不加载原图；
- `imageBytes(id)`：选中时才读原图字节，交给本地引擎。

UI 在 `lib/widgets/gallery_sheet.dart`，首页与检测页共用；相机仍走 `ACTION_IMAGE_CAPTURE`（不需要读外部 URI）。

### 实机验证记录（2026-11-16）

| 场景 | 结果 |
|---|---|
| 设置 → 本地引擎自检 | 通过，PSNR 54.3 dB、SSIM 0.996、k=14、耗时 594 ms |
| 内置相册选图 → 嵌入 | 通过，PSNR 45.9–46.x dB，结果页正常 |
| 保存到相册 | 通过，写入 `/sdcard/Pictures/InvisMark/<trace_id>.png` |
| 检测同一张成图 | 命中，置信 100%，trace_id/资源码/嵌入时间一致 |

截图：`docs/apk-gallery-sheet-screenshot.png`、`docs/apk-embed-result-screenshot.png`、`docs/apk-detect-hit-screenshot.png`。

### 桌面端数据目录

PyInstaller 单文件默认把 SQLite 写到启动时的工作目录，双击运行时可能是只读目录 → 启动即失败。
现在默认写 `%APPDATA%\InvisMark\invismark.db`（`INVISMARK_DB` 可覆盖），初始化失败会弹窗提示而不是闪退。

---

## 3. 发布 Release 建议

```text
v0.1.0
├─ InvisMark-0.1.0-win64-gui.exe
├─ InvisMark-0.1.0-win64-cli.exe
├─ InvisMark-0.1.0-win64-portable.zip
├─ InvisMark-0.1.0-android.apk
├─ invismark-0.1.0-py3-none-any.whl
├─ invismark-0.1.0-source.zip / .tar.gz
├─ invismark-0.1.0.bundle
└─ SHA256SUMS.txt
```

> 版本号与 `invismark/_version.py`、`pyproject.toml`、`pubspec.yaml` 三处保持一致。
