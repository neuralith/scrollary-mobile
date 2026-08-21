// Generates every raster the app's identity needs, from one definition of the
// mark: iOS app icon slots, Android legacy + adaptive icons, both platforms'
// launch images, and the Flutter asset the in-app splash draws.
//
// Run from the repository root:
//
//     swift tool/brand/generate_brand_assets.swift
//
// Deliberately a script over CoreGraphics rather than a package: the icon is
// generated once and committed, and this repo does not take a dependency to
// draw two shapes. Colours are the app palette's (lib/ui/palette.dart) — the
// mark and the UI are the same design.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

/// Ground gradient, derived from `AppPalette.primary` (#33606F).
let groundTop: UInt32 = 0x3E6D7E
let groundBottom: UInt32 = 0x21444E
/// `AppPalette.surface` — the page the app draws everything else on.
let pageCream: UInt32 = 0xF8F6F2
/// The shadowed under-page, giving the book thickness.
let pageShade: UInt32 = 0xCBC3B5
/// `AppPalette.toastAccent` — the arrow.
let accent: UInt32 = 0x9CC0CB

func cgColor(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha)
}

// MARK: - The mark
//
// Everything is drawn in a 1024×1024 design space with the origin at the top
// left, so the numbers below read the way the artwork does.

let design: CGFloat = 1024

/// The arrow: a shaft and a head, pointing down into the book's centrefold.
/// The tip stops just short of the pages — it is arriving, not landed.
func addArrow(_ ctx: CGContext) {
  let shaftHalf: CGFloat = 38
  let headHalf: CGFloat = 116
  let path = CGMutablePath()
  path.move(to: CGPoint(x: 512 - shaftHalf, y: 214))
  path.addLine(to: CGPoint(x: 512 + shaftHalf, y: 214))
  path.addLine(to: CGPoint(x: 512 + shaftHalf, y: 392))
  path.addLine(to: CGPoint(x: 512 + headHalf, y: 392))
  path.addLine(to: CGPoint(x: 512, y: 588))
  path.addLine(to: CGPoint(x: 512 - headHalf, y: 392))
  path.addLine(to: CGPoint(x: 512 - shaftHalf, y: 392))
  path.closeSubpath()
  ctx.addPath(path)
}

/// One page of the open book, hinged at the spine.
///
/// `mirrored` reflects the same geometry across the spine, so the two halves
/// can never drift apart.
func pagePath(mirrored: Bool, dy: CGFloat = 0) -> CGPath {
  let p = CGMutablePath()
  // Spine-side top, sweeping out to the far top corner: the centre sits lower
  // than the outer edge, which is what makes it read as a book and not a card.
  p.move(to: CGPoint(x: 500, y: 626 + dy))
  p.addCurve(
    to: CGPoint(x: 214, y: 570 + dy),
    control1: CGPoint(x: 416, y: 576 + dy),
    control2: CGPoint(x: 316, y: 558 + dy))
  p.addCurve(
    to: CGPoint(x: 182, y: 604 + dy),
    control1: CGPoint(x: 196, y: 572 + dy),
    control2: CGPoint(x: 182, y: 584 + dy))
  p.addLine(to: CGPoint(x: 182, y: 736 + dy))
  p.addCurve(
    to: CGPoint(x: 214, y: 770 + dy),
    control1: CGPoint(x: 182, y: 754 + dy),
    control2: CGPoint(x: 196, y: 768 + dy))
  p.addCurve(
    to: CGPoint(x: 500, y: 806 + dy),
    control1: CGPoint(x: 316, y: 758 + dy),
    control2: CGPoint(x: 416, y: 766 + dy))
  p.closeSubpath()

  guard mirrored else { return p }
  var flip = CGAffineTransform(translationX: design, y: 0).scaledBy(x: -1, y: 1)
  return p.copy(using: &flip) ?? p
}

func drawGlyph(_ ctx: CGContext) {
  // Under-page first: the same silhouette, dropped, so each half has an edge.
  ctx.setFillColor(cgColor(pageShade))
  ctx.addPath(pagePath(mirrored: false, dy: 22))
  ctx.addPath(pagePath(mirrored: true, dy: 22))
  ctx.fillPath()

  ctx.setFillColor(cgColor(pageCream))
  ctx.addPath(pagePath(mirrored: false))
  ctx.addPath(pagePath(mirrored: true))
  ctx.fillPath()

  ctx.setFillColor(cgColor(accent))
  addArrow(ctx)
  ctx.fillPath()
}

enum Ground {
  /// Full-bleed square: iOS masks the corners itself, and a pre-rounded icon
  /// would show a light seam inside the mask.
  case square
  /// Rounded tile on transparency, for launchers and surfaces that expect the
  /// artwork to carry its own shape.
  case tile
  /// Glyph only, for the Android adaptive foreground layer.
  case none
}

func render(size: Int, ground: Ground, to url: URL) {
  let px = CGFloat(size)
  guard
    let ctx = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { fatalError("cannot create a \(size)px context") }

  ctx.interpolationQuality = .high
  ctx.setAllowsAntialiasing(true)
  // Flip into the top-left design space, then scale it onto the bitmap.
  ctx.translateBy(x: 0, y: px)
  ctx.scaleBy(x: 1, y: -1)
  ctx.scaleBy(x: px / design, y: px / design)

  if ground != .none {
    ctx.saveGState()
    if ground == .tile {
      // Matches the iOS mask closely enough that the two read as one icon.
      ctx.addPath(
        CGPath(
          roundedRect: CGRect(x: 0, y: 0, width: design, height: design),
          cornerWidth: design * 0.2237, cornerHeight: design * 0.2237,
          transform: nil))
      ctx.clip()
    }
    let gradient = CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      colors: [cgColor(groundTop), cgColor(groundBottom)] as CFArray,
      locations: [0, 1])!
    ctx.drawLinearGradient(
      gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: design),
      options: [])
    ctx.restoreGState()
    drawGlyph(ctx)
  } else {
    // The adaptive foreground must stay inside the 66/108 safe zone, so the
    // glyph — not the canvas — is what gets centred and scaled.
    let scale: CGFloat = 0.80
    ctx.translateBy(x: design / 2, y: design / 2)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -design / 2, y: -510)
    drawGlyph(ctx)
  }

  guard let image = ctx.makeImage(),
    let dest = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { fatalError("cannot write \(url.path)") }
  CGImageDestinationAddImage(dest, image, nil)
  guard CGImageDestinationFinalize(dest) else { fatalError("cannot finalize \(url.path)") }
  print("  \(url.lastPathComponent) (\(size)px)")
}

// MARK: - Outputs

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func out(_ path: String) -> URL {
  let url = root.appendingPathComponent(path)
  try! FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  return url
}

print("iOS app icon")
let iosIcons: [(String, Int)] = [
  ("Icon-App-20x20@1x.png", 20), ("Icon-App-20x20@2x.png", 40),
  ("Icon-App-20x20@3x.png", 60), ("Icon-App-29x29@1x.png", 29),
  ("Icon-App-29x29@2x.png", 58), ("Icon-App-29x29@3x.png", 87),
  ("Icon-App-40x40@1x.png", 40), ("Icon-App-40x40@2x.png", 80),
  ("Icon-App-40x40@3x.png", 120), ("Icon-App-60x60@2x.png", 120),
  ("Icon-App-60x60@3x.png", 180), ("Icon-App-76x76@1x.png", 76),
  ("Icon-App-76x76@2x.png", 152), ("Icon-App-83.5x83.5@2x.png", 167),
  ("Icon-App-1024x1024@1x.png", 1024),
]
for (name, size) in iosIcons {
  render(size: size, ground: .square, to: out("ios/Runner/Assets.xcassets/AppIcon.appiconset/\(name)"))
}

print("iOS launch image (96pt tile)")
for (name, size) in [("LaunchImage.png", 96), ("LaunchImage@2x.png", 192), ("LaunchImage@3x.png", 288)] {
  render(size: size, ground: .tile, to: out("ios/Runner/Assets.xcassets/LaunchImage.imageset/\(name)"))
}

// mdpi is 1x; every other bucket is a multiple of it.
let densities: [(String, CGFloat)] = [
  ("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4),
]

print("Android launcher icon")
for (bucket, scale) in densities {
  render(
    size: Int(48 * scale), ground: .tile,
    to: out("android/app/src/main/res/mipmap-\(bucket)/ic_launcher.png"))
  render(
    size: Int(108 * scale), ground: .none,
    to: out("android/app/src/main/res/mipmap-\(bucket)/ic_launcher_foreground.png"))
}

print("Android launch image (96dp tile)")
for (bucket, scale) in densities {
  render(
    size: Int(96 * scale), ground: .tile,
    to: out("android/app/src/main/res/drawable-\(bucket)/launch_mark.png"))
}

print("Flutter asset")
render(size: 1024, ground: .tile, to: out("assets/brand/app_mark.png"))
