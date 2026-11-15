// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 纯 Dart PNG 编解码（零第三方依赖，zlib 用 dart:io 自带实现）。
// 解码支持：8/16bit、灰度/RGB/调色板/灰度+Alpha/RGBA、非隔行；
// 解码输出统一 RGBA（Alpha 按白底合成）。
// 编码输出：8bit RGB、非隔行、filter=None（与 Python 版一致）。

import 'dart:io';
import 'dart:typed_data';

class ImageData {
  ImageData({required this.width, required this.height, required this.rgba});

  final int width;
  final int height;

  /// 长度 = width * height * 4，顺序 R,G,B,A
  final Uint8List rgba;

  ImageData copy() => ImageData(width: width, height: height, rgba: Uint8List.fromList(rgba));
}

class PngCodec {
  PngCodec._();

  static const List<int> _signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  static bool isPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  static ImageData decode(Uint8List bytes) {
    if (!isPng(bytes)) {
      throw const FormatException('不是 PNG 文件');
    }
    final ByteData data = ByteData.sublistView(bytes);
    int pos = 8;
    int width = 0;
    int height = 0;
    int depth = 0;
    int colorType = 0;
    int interlace = 0;
    Uint8List? palette;
    final BytesBuilder idat = BytesBuilder(copy: true);

    while (pos + 8 <= bytes.length) {
      final int length = data.getUint32(pos);
      final String type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      final int bodyStart = pos + 8;
      final Uint8List body = bytes.sublist(bodyStart, bodyStart + length);
      pos = bodyStart + length + 4; // 跳过 CRC
      if (type == 'IHDR') {
        width = ByteData.sublistView(body).getUint32(0);
        height = ByteData.sublistView(body).getUint32(4);
        depth = body[8];
        colorType = body[9];
        interlace = body[12];
      } else if (type == 'PLTE') {
        palette = body;
      } else if (type == 'IDAT') {
        idat.add(body);
      } else if (type == 'IEND') {
        break;
      }
    }
    if (width <= 0 || height <= 0) {
      throw const FormatException('PNG 缺少 IHDR');
    }
    if (interlace != 0) {
      throw const FormatException('不支持隔行 PNG');
    }
    final int channels = switch (colorType) {
      0 => 1,
      2 => 3,
      3 => 1,
      4 => 2,
      6 => 4,
      _ => throw FormatException('不支持的颜色类型 $colorType'),
    };
    if (depth != 8 && depth != 16) {
      throw FormatException('不支持的位深 $depth');
    }
    final int bpp = channels * (depth == 16 ? 2 : 1);
    final int stride = width * bpp;

    final List<int> raw = ZLibCodec(level: 6).decode(idat.takeBytes());
    final Uint8List pixels = Uint8List(height * stride);
    int p = 0;
    for (int y = 0; y < height; y++) {
      final int filter = raw[p++];
      final int rowStart = y * stride;
      final int prevStart = rowStart - stride;
      for (int x = 0; x < stride; x++) {
        final int rawByte = raw[p++];
        final int left = x >= bpp ? pixels[rowStart + x - bpp] : 0;
        final int up = y > 0 ? pixels[prevStart + x] : 0;
        final int upLeft = (y > 0 && x >= bpp) ? pixels[prevStart + x - bpp] : 0;
        int value;
        switch (filter) {
          case 0:
            value = rawByte;
          case 1:
            value = rawByte + left;
          case 2:
            value = rawByte + up;
          case 3:
            value = rawByte + ((left + up) >> 1);
          case 4:
            final int pa = (left + up - upLeft).abs();
            final int pb = (up - upLeft).abs();
            final int pc = (left - up).abs();
            int pr;
            if (pa <= pb && pa <= pc) {
              pr = left;
            } else if (pb <= pc) {
              pr = up;
            } else {
              pr = upLeft;
            }
            value = rawByte + pr;
          default:
            throw FormatException('未知 PNG filter $filter');
        }
        pixels[rowStart + x] = value & 0xFF;
      }
    }

    // 展开为 RGBA
    final Uint8List rgba = Uint8List(width * height * 4);
    int out = 0;
    final int step = depth == 16 ? 2 : 1; // 16bit 取高字节
    for (int y = 0; y < height; y++) {
      final int rowStart = y * stride;
      for (int x = 0; x < width; x++) {
        final int base = rowStart + x * bpp;
        int r;
        int g;
        int b;
        int a = 255;
        switch (colorType) {
          case 0:
            r = g = b = pixels[base];
          case 2:
            r = pixels[base];
            g = pixels[base + step];
            b = pixels[base + 2 * step];
          case 3:
            final int idx = pixels[base];
            if (palette == null || idx * 3 + 2 >= palette.length) {
              throw const FormatException('调色板越界');
            }
            r = palette[idx * 3];
            g = palette[idx * 3 + 1];
            b = palette[idx * 3 + 2];
          case 4:
            r = g = b = pixels[base];
            a = pixels[base + step];
          case 6:
            r = pixels[base];
            g = pixels[base + step];
            b = pixels[base + 2 * step];
            a = pixels[base + 3 * step];
          default:
            throw const FormatException('不支持的颜色类型');
        }
        if (a != 255) {
          // 白底合成
          r = ((r * a + 255 * (255 - a)) / 255).round();
          g = ((g * a + 255 * (255 - a)) / 255).round();
          b = ((b * a + 255 * (255 - a)) / 255).round();
          a = 255;
        }
        rgba[out++] = r;
        rgba[out++] = g;
        rgba[out++] = b;
        rgba[out++] = a;
      }
    }
    return ImageData(width: width, height: height, rgba: rgba);
  }

  static Uint8List encode(ImageData image) {
    final int width = image.width;
    final int height = image.height;
    final Uint8List rgba = image.rgba;
    final Uint8List rows = Uint8List(height * (width * 3 + 1));
    int p = 0;
    int q = 0;
    for (int y = 0; y < height; y++) {
      rows[p++] = 0; // filter None
      for (int x = 0; x < width; x++) {
        rows[p++] = rgba[q];
        rows[p++] = rgba[q + 1];
        rows[p++] = rgba[q + 2];
        q += 4;
      }
    }
    final List<int> compressed = ZLibCodec(level: 6).encode(rows);
    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(_signature);
    out.add(_chunk('IHDR', _ihdr(width, height)));
    out.add(_chunk('IDAT', Uint8List.fromList(compressed)));
    out.add(_chunk('IEND', Uint8List(0)));
    return out.takeBytes();
  }

  static Uint8List _ihdr(int width, int height) {
    final Uint8List body = Uint8List(13);
    final ByteData bd = ByteData.sublistView(body);
    bd.setUint32(0, width);
    bd.setUint32(4, height);
    body[8] = 8; // bit depth
    body[9] = 2; // RGB
    body[10] = 0;
    body[11] = 0;
    body[12] = 0;
    return body;
  }

  static Uint8List _chunk(String type, Uint8List body) {
    final Uint8List typeBytes = Uint8List.fromList(type.codeUnits);
    final BytesBuilder builder = BytesBuilder(copy: false);
    final ByteData len = ByteData(4)..setUint32(0, body.length);
    builder.add(len.buffer.asUint8List());
    builder.add(typeBytes);
    builder.add(body);
    final int crc = TraceCrc.crc32(<int>[...typeBytes, ...body]);
    final ByteData crcData = ByteData(4)..setUint32(0, crc);
    builder.add(crcData.buffer.asUint8List());
    return builder.takeBytes();
  }
}

/// PNG 分块需要 CRC32；单独暴露一个小工具，避免和 trace 模块耦合。
class TraceCrc {
  TraceCrc._();

  static final List<int> _table = _build();

  static List<int> _build() {
    final List<int> table = List<int>.filled(256, 0);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int i = 0; i < 8; i++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  static int crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final int b in data) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
