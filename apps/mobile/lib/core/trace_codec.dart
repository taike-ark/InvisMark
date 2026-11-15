// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 24 字节追溯码：版本(1) + base36 资源码(4) + 用户索引(2) + 分钟时间(4)
// + 序号(4) + CRC32(4) + 保留位(5)。布局与 Python 版 invismark/core/trace.py 完全一致，
// 两端互读（Python 服务端提取到的码，移动端也能解析）。

class TraceCode {
  const TraceCode({
    required this.resourceCode,
    required this.userIndex,
    required this.embeddedAt,
    this.serial = 0,
  });

  static const int length = 24;
  static const int version = 1;
  static const String alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// UTC 分钟起点：2020-01-01T00:00:00Z
  static final DateTime epoch = DateTime.utc(2020, 1, 1);

  final String resourceCode;
  final int userIndex;
  final DateTime embeddedAt;
  final int serial;

  static String _pad6(String code) {
    final String upper = code.trim().toUpperCase();
    if (upper.isEmpty || upper.length > 6) {
      throw FormatException('resource_code 必须是 1..6 位 base36', code);
    }
    return upper.padLeft(6, '0');
  }

  static int _encodeCode(String code) {
    final String padded = _pad6(code);
    int value = 0;
    for (final String ch in padded.split('')) {
      final int idx = alphabet.indexOf(ch);
      if (idx < 0) {
        throw FormatException('resource_code 含非法字符', ch);
      }
      value = value * 36 + idx;
    }
    return value;
  }

  static String _decodeCode(int value) {
    int v = value;
    final List<String> chars = <String>[];
    for (int i = 0; i < 6; i++) {
      chars.add(alphabet[v % 36]);
      v ~/= 36;
    }
    return chars.reversed.join();
  }

  factory TraceCode.newCode({
    required String resourceCode,
    required int userIndex,
    DateTime? embeddedAt,
    int serial = 0,
  }) {
    if (userIndex < 0 || userIndex > 0xFFFF) {
      throw FormatException('user_index 越界', '$userIndex');
    }
    return TraceCode(
      resourceCode: _pad6(resourceCode),
      userIndex: userIndex,
      embeddedAt: (embeddedAt ?? DateTime.now().toUtc()).toUtc(),
      serial: serial,
    );
  }

  int get minute {
    return embeddedAt.difference(epoch).inMinutes;
  }

  List<int> toBytes() {
    final int resource = _encodeCode(resourceCode);
    final int minuteValue = minute;
    final List<int> head = <int>[
      version,
      (resource >> 24) & 0xFF,
      (resource >> 16) & 0xFF,
      (resource >> 8) & 0xFF,
      resource & 0xFF,
      (userIndex >> 8) & 0xFF,
      userIndex & 0xFF,
      (minuteValue >> 24) & 0xFF,
      (minuteValue >> 16) & 0xFF,
      (minuteValue >> 8) & 0xFF,
      minuteValue & 0xFF,
      (serial >> 24) & 0xFF,
      (serial >> 16) & 0xFF,
      (serial >> 8) & 0xFF,
      serial & 0xFF,
    ];
    final int crc = crc32(head);
    return <int>[
      ...head,
      (crc >> 24) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 8) & 0xFF,
      crc & 0xFF,
      0,
      0,
      0,
      0,
      0,
    ];
  }

  String get hex => toBytes().map((int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();

  static TraceCode fromBytes(List<int> bytes) {
    if (bytes.length != length) {
      throw const FormatException('trace_id 必须是 24 字节');
    }
    if (bytes[0] != version) {
      throw const FormatException('不支持的版本号');
    }
    final int crc = (bytes[15] << 24) | (bytes[16] << 16) | (bytes[17] << 8) | bytes[18];
    if (crc32(bytes.sublist(0, 15)) != crc) {
      throw const FormatException('CRC32 校验失败');
    }
    for (int i = 19; i < 24; i++) {
      if (bytes[i] != 0) {
        throw const FormatException('保留位必须为 0');
      }
    }
    final int resource = (bytes[1] << 24) | (bytes[2] << 16) | (bytes[3] << 8) | bytes[4];
    final int userIndex = (bytes[5] << 8) | bytes[6];
    final int minuteValue = (bytes[7] << 24) | (bytes[8] << 16) | (bytes[9] << 8) | bytes[10];
    final int serial = (bytes[11] << 24) | (bytes[12] << 16) | (bytes[13] << 8) | bytes[14];
    return TraceCode(
      resourceCode: _decodeCode(resource),
      userIndex: userIndex,
      embeddedAt: epoch.add(Duration(minutes: minuteValue)),
      serial: serial,
    );
  }

  static TraceCode fromHex(String hex) {
    final String cleaned = hex.trim().replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final List<int> bytes = <int>[];
    for (int i = 0; i + 1 < cleaned.length; i += 2) {
      bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
    }
    return fromBytes(bytes);
  }

  static final List<int> _crcTable = _buildCrcTable();

  static List<int> _buildCrcTable() {
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
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
