// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 入口：runApp + MaterialApp（亮/暗主题均来自 tokens.dart），标题「隐迹 InvisMark」。

import 'package:flutter/material.dart';

import 'app.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() {
  // TODO(M3): 原生插件初始化（相机/相册/本地通知）与崩溃上报在这里接入
  runApp(const InvisMarkApp());
}

class InvisMarkApp extends StatefulWidget {
  const InvisMarkApp({super.key});

  @override
  State<InvisMarkApp> createState() => _InvisMarkAppState();
}

class _InvisMarkAppState extends State<InvisMarkApp> {
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (BuildContext context, Widget? child) => MaterialApp(
          title: '隐迹 InvisMark',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _state.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}
