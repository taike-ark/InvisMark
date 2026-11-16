// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 内置相册选择器：直接读系统 MediaStore 列出最近图片，避免系统文件选择器
// 在不同 ROM 上返回不可读 URI 导致「选完图没反应」。

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/native_media.dart';
import '../theme/tokens.dart';
import 'glass_button.dart';
import 'glass_container.dart';

Future<PickedImage?> showGallerySheet(BuildContext context) {
  return showModalBottomSheet<PickedImage>(
    context: context,
    backgroundColor: AppBrand.clear,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => const _GallerySheet(),
  );
}

class _GallerySheet extends StatefulWidget {
  const _GallerySheet();

  @override
  State<_GallerySheet> createState() => _GallerySheetState();
}

class _GallerySheetState extends State<_GallerySheet> {
  List<GalleryImage>? _images;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<GalleryImage> images = await NativeMedia.listImages();
      if (!mounted) return;
      setState(() {
        _images = images;
        _loading = false;
      });
    } on NativeMediaException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _choose(GalleryImage image) async {
    try {
      final PickedImage picked = await NativeMedia.imageBytes(image.id);
      if (!mounted) return;
      Navigator.of(context).pop(picked);
    } on NativeMediaException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), duration: AppMotion.toast),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double bottomInset = MediaQuery.maybeOf(context)?.viewPadding.bottom ?? 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.page,
          AppSpacing.page,
          AppSpacing.page + bottomInset,
        ),
        child: GlassContainer(
          radius: AppRadius.xl,
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '选择图片（本机相册）',
                      style: AppType.title2.copyWith(color: palette.glassTextPrimary),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: palette.glassTextSecondary),
                    tooltip: '取消',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '图片只在本机处理，不会上传。首次使用会请求相册读取权限。',
                style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 360,
                child: _buildBody(palette),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            GlassSecondaryButton(
              label: '重试',
              semanticsLabel: '重新读取相册',
              onPressed: _load,
            ),
          ],
        ),
      );
    }
    final List<GalleryImage> images = _images ?? const <GalleryImage>[];
    if (images.isEmpty) {
      return Center(
        child: Text(
          '相册里还没有图片',
          style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: images.length,
      itemBuilder: (BuildContext context, int index) {
        final GalleryImage image = images[index];
        return GestureDetector(
          onTap: () => _choose(image),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: _Thumb(image: image),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image});

  final GalleryImage image;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: NativeMedia.thumbnail(image.id, max: 260),
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(snapshot.data!, fit: BoxFit.cover);
        }
        return ColoredBox(
          color: const Color(0xFF2A2E35),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator(strokeWidth: 1.5)
                  : const Icon(Icons.image_not_supported_outlined, size: 16),
            ),
          ),
        );
      },
    );
  }
}
