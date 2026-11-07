import 'dart:typed_data';

/// Reads the pixel size of a PNG, GIF, JPEG or WebP image from its header,
/// without decoding it. Returns null for other formats or truncated data.
///
/// Knowing the size before decoding keeps the layout stable, so restored
/// reading positions do not drift when images finish loading.
({int width, int height})? readImageSize(Uint8List b) {
  int be16(int i) => (b[i] << 8) | b[i + 1];
  int le16(int i) => b[i] | (b[i + 1] << 8);
  int be32(int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  int le24(int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16);
  ({int width, int height})? ok(int w, int h) =>
      w > 0 && h > 0 ? (width: w, height: h) : null;

  try {
    // PNG: signature, then the IHDR chunk.
    if (b.length >= 24 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return ok(be32(16), be32(20));
    }
    // GIF87a / GIF89a.
    if (b.length >= 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return ok(le16(6), le16(8));
    }
    // JPEG: walk the segments to a start-of-frame marker.
    if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          return ok(be16(i + 7), be16(i + 5));
        }
        if (marker == 0xD8 ||
            (marker >= 0xD0 && marker <= 0xD7) ||
            marker == 0x01) {
          i += 2;
          continue;
        }
        i += 2 + be16(i + 2);
      }
      return null;
    }
    // WebP: RIFF....WEBP
    if (b.length >= 30 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 && //
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      final chunk = String.fromCharCodes(b.sublist(12, 16));
      switch (chunk) {
        case 'VP8X':
          return ok(1 + le24(24), 1 + le24(27));
        case 'VP8L':
          final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
          return ok(1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF));
        case 'VP8 ':
          return ok(le16(26) & 0x3FFF, le16(28) & 0x3FFF);
      }
    }
  } on RangeError {
    return null;
  }
  return null;
}
