// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 冒烟测试：App 能 pump 起来，首页显示产品标题，且玻璃组件已经挂在树上。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invismark_mobile/main.dart';
import 'package:invismark_mobile/theme/tokens.dart';
import 'package:invismark_mobile/widgets/glass_container.dart';

void main() {
  testWidgets('首页渲染出产品标题与玻璃组件', (WidgetTester tester) async {
    // 固定成常见手机尺寸（360×780 逻辑像素），避免不同宿主影响布局
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const InvisMarkApp());

    // 冷启动首帧是 Opaque 档，200ms 后才切到真实档位；
    // 等这个定时器走完，否则测试结束时会报 pending timer。
    await tester.pump(AppLayout.coldStartOpaqueHold + const Duration(milliseconds: 20));
    await tester.pump();

    expect(find.text('隐迹 InvisMark'), findsOneWidget);
    expect(find.byType(GlassContainer), findsWidgets);
    expect(find.text('选择图片嵌入水印'), findsOneWidget);
  });
}
