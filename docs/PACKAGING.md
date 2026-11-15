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
   `Unresolved reference 'compilerOptions'`——纯 Dart 应用直接删掉这个块即可。
5. **国内镜像**：`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、
   `PUB_HOSTED_URL=https://pub.flutter-io.cn`；Gradle 可用腾讯/阿里云镜像。
6. 构建机容器/沙箱里，`APPDATA`、`TEMP`、`GRADLE_USER_HOME`、`ANDROID_USER_HOME`
   都要指到可写目录，否则 Dart/Flutter 工具会因写 `.flutter_tool_state` 失败而退出。

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
