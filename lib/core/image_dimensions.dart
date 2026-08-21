/// Read an image's real pixel dimensions from its bytes.
///
/// This is the source of truth for stored assets: HTML attributes lie,
/// placeholder boxes lie, CSS-rendered sizes are layout rather than pixels,
/// and a WebView's report is a snapshot taken at whatever moment the probe
/// ran. The downloaded file itself cannot lie about its own header.
///
/// Pure Dart, headers only — no frame is decoded, so this is cheap enough to
/// run per asset at save time and per file when the reader verifies a
/// manifest. Covers exactly the formats `detectImageMime` accepts: PNG, JPEG,
/// GIF, WebP, BMP, and the ISO-BMFF family (AVIF/HEIC/HEIF).
library;

import 'dart:typed_data';

class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;

  bool get isValid => width > 0 && height > 0;
  double get aspect => height == 0 ? 0 : width / height;

  @override
  String toString() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      other is ImageDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Dimensions from the file header, or null when the bytes are not a
/// recognised image (or are truncated before the size is declared).
ImageDimensions? readImageDimensions(Uint8List b) {
  if (b.length < 12) return null;

  // PNG: IHDR is required to be the first chunk — width/height at offset 16.
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) {
    if (b.length < 24) return null;
    return _valid(_u32be(b, 16), _u32be(b, 20));
  }

  // JPEG: walk segments to the first SOFn, honouring EXIF orientation.
  if (b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
    return _jpeg(b);
  }

  // GIF: logical screen descriptor, little-endian, right after "GIF87a/89a".
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return _valid(_u16le(b, 6), _u16le(b, 8));
  }

  // BMP: BITMAPINFOHEADER at offset 14; height may be negative (top-down).
  if (b[0] == 0x42 && b[1] == 0x4d) {
    if (b.length < 26) return null;
    final headerSize = _u32le(b, 14);
    if (headerSize >= 40) {
      final h = _i32le(b, 22);
      return _valid(_i32le(b, 18), h < 0 ? -h : h);
    }
    // Ancient BITMAPCOREHEADER: 16-bit fields.
    return _valid(_u16le(b, 18), _u16le(b, 20));
  }

  // WebP: RIFF....WEBP, then a VP8/VP8L/VP8X chunk.
  if (b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b.length >= 16 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return _webp(b);
  }

  // ISO base media file format: '....ftyp' — AVIF, HEIC, HEIF.
  if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    return _isoBmff(b);
  }

  return null;
}

ImageDimensions? _valid(int w, int h) =>
    (w > 0 && h > 0) ? ImageDimensions(w, h) : null;

// --- JPEG --------------------------------------------------------------

ImageDimensions? _jpeg(Uint8List b) {
  int? orientation;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xff) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    // Standalone markers with no payload.
    if (marker == 0xd8 ||
        (marker >= 0xd0 && marker <= 0xd7) ||
        marker == 0x01) {
      i += 2;
      continue;
    }
    if (marker == 0xd9 || marker == 0xda) break; // EOI / start of scan
    final length = (b[i + 2] << 8) | b[i + 3];
    if (length < 2) return null;

    // APP1/EXIF: remember the orientation so rotated files report the
    // dimensions the decoder will actually produce.
    if (marker == 0xe1 && i + 4 + 6 <= b.length) {
      orientation ??= _exifOrientation(b, i + 4, length - 2);
    }

    // SOF0..SOF15 except DHT(C4)/JPGA?(C8)/DAC(CC) carry the frame size.
    if (marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc) {
      if (i + 9 > b.length) return null;
      final height = (b[i + 5] << 8) | b[i + 6];
      final width = (b[i + 7] << 8) | b[i + 8];
      // Orientations 5-8 are 90°/270° rotations: the decoded image is
      // transposed relative to the frame header.
      final swap = orientation != null && orientation >= 5 && orientation <= 8;
      return _valid(swap ? height : width, swap ? width : height);
    }
    i += 2 + length;
  }
  return null;
}

/// EXIF orientation (1..8) from an APP1 payload, or null.
int? _exifOrientation(Uint8List b, int start, int length) {
  final end = start + length;
  if (start + 14 > b.length || end > b.length) return null;
  // "Exif\0\0"
  if (b[start] != 0x45 ||
      b[start + 1] != 0x78 ||
      b[start + 2] != 0x69 ||
      b[start + 3] != 0x66) {
    return null;
  }
  final tiff = start + 6;
  final bool little;
  if (b[tiff] == 0x49 && b[tiff + 1] == 0x49) {
    little = true;
  } else if (b[tiff] == 0x4d && b[tiff + 1] == 0x4d) {
    little = false;
  } else {
    return null;
  }
  int u16(int o) => little ? _u16le(b, o) : ((b[o] << 8) | b[o + 1]);
  int u32(int o) => little ? _u32le(b, o) : _u32be(b, o);

  final ifdOffset = u32(tiff + 4);
  final ifd = tiff + ifdOffset;
  if (ifd + 2 > end) return null;
  final entries = u16(ifd);
  for (var e = 0; e < entries; e++) {
    final entry = ifd + 2 + e * 12;
    if (entry + 12 > end) return null;
    if (u16(entry) == 0x0112) {
      final value = u16(entry + 8);
      return (value >= 1 && value <= 8) ? value : null;
    }
  }
  return null;
}

// --- WebP --------------------------------------------------------------

ImageDimensions? _webp(Uint8List b) {
  final fourcc = String.fromCharCodes(b.sublist(12, 16));
  switch (fourcc) {
    case 'VP8X':
      // 24-bit canvas size minus one, at offsets 24 and 27.
      if (b.length < 30) return null;
      final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return _valid(w, h);
    case 'VP8 ':
      // Lossy: frame tag then 3-byte start code 9D 01 2A, then 14-bit dims.
      if (b.length < 30) return null;
      if (b[23] != 0x9d || b[24] != 0x01 || b[25] != 0x2a) return null;
      return _valid(_u16le(b, 26) & 0x3fff, _u16le(b, 28) & 0x3fff);
    case 'VP8L':
      // Lossless: signature 0x2F then 14+14 bits packed little-endian.
      if (b.length < 25 || b[20] != 0x2f) return null;
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return _valid(1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff));
  }
  return null;
}

// --- ISO-BMFF (AVIF / HEIC / HEIF) ---------------------------------------

/// Walk `meta → iprp → ipco` and read `ispe` boxes.
///
/// An AVIF can carry several `ispe` properties (thumbnail, alpha plane,
/// grid tiles); the largest one belongs to the full image on every real file
/// seen, and picking the largest can never turn a correct answer into a
/// smaller wrong one for layout purposes.
ImageDimensions? _isoBmff(Uint8List b) {
  ImageDimensions? best;

  void scan(int start, int end, int depth) {
    if (depth > 6) return;
    var i = start;
    while (i + 8 <= end) {
      var size = _u32be(b, i);
      final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
      var header = 8;
      if (size == 1) {
        if (i + 16 > end) return;
        // 64-bit size; the low word is all that can matter here.
        size = _u32be(b, i + 12);
        header = 16;
      } else if (size == 0) {
        size = end - i; // box extends to end of file
      }
      if (size < header || i + size > end) return;

      switch (type) {
        case 'meta':
          // Full box: 4 bytes of version/flags before the children.
          scan(i + header + 4, i + size, depth + 1);
        case 'iprp' || 'ipco':
          scan(i + header, i + size, depth + 1);
        case 'ispe':
          if (i + header + 12 <= end) {
            final w = _u32be(b, i + header + 4);
            final h = _u32be(b, i + header + 8);
            final dims = _valid(w, h);
            if (dims != null &&
                (best == null ||
                    dims.width * dims.height > best!.width * best!.height)) {
              best = dims;
            }
          }
      }
      i += size;
    }
  }

  scan(0, b.length, 0);
  return best;
}

// --- byte readers --------------------------------------------------------

int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32be(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _u32le(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
int _i32le(Uint8List b, int o) {
  final v = _u32le(b, o);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}
