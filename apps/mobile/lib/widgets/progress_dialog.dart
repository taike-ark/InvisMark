// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 统一的过程提示：本地引擎处理一张 1600px 图约 1–3 秒，期间必须有可见反馈，
// 否则用户会以为“点了没反应”。

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

Future<T> runWithProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: dialogContext.isDarkMode
            ? const Color(0xFF1C1F24)
            : const Color(0xFFF7F8FA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.lg),
              Flexible(
                child: Text(
                  message,
                  style: AppType.body,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

extension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
