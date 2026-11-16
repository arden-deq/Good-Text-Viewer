#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
  fputs("usage: make-qa-comparison.swift <reference> <implementation> <output>\n", stderr)
  exit(64)
}

let referenceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let implementationURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard
  let reference = NSImage(contentsOf: referenceURL),
  let implementation = NSImage(contentsOf: implementationURL)
else {
  fputs("could not load one or more input images\n", stderr)
  exit(66)
}

let panelHeight: CGFloat = 720
let labelHeight: CGFloat = 46
let outerPadding: CGFloat = 28
let gap: CGFloat = 28

func fittedSize(for image: NSImage) -> NSSize {
  let scale = panelHeight / image.size.height
  return NSSize(width: round(image.size.width * scale), height: panelHeight)
}

let referenceSize = fittedSize(for: reference)
let implementationSize = fittedSize(for: implementation)
let canvasSize = NSSize(
  width: outerPadding * 2 + referenceSize.width + gap + implementationSize.width,
  height: outerPadding * 2 + labelHeight + panelHeight
)

guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fputs("could not allocate comparison bitmap\n", stderr)
  exit(70)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let referenceOrigin = NSPoint(x: outerPadding, y: outerPadding)
let implementationOrigin = NSPoint(x: outerPadding + referenceSize.width + gap, y: outerPadding)

reference.draw(
  in: NSRect(origin: referenceOrigin, size: referenceSize),
  from: .zero,
  operation: .sourceOver,
  fraction: 1,
  respectFlipped: true,
  hints: [.interpolation: NSImageInterpolation.high]
)
implementation.draw(
  in: NSRect(origin: implementationOrigin, size: implementationSize),
  from: .zero,
  operation: .sourceOver,
  fraction: 1,
  respectFlipped: true,
  hints: [.interpolation: NSImageInterpolation.high]
)

let labelStyle = NSMutableParagraphStyle()
labelStyle.alignment = .center
let labelAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
  .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1),
  .paragraphStyle: labelStyle,
]

let labelY = outerPadding + panelHeight + 13
NSAttributedString(string: "수정 전", attributes: labelAttributes).draw(
  in: NSRect(x: referenceOrigin.x, y: labelY, width: referenceSize.width, height: 24)
)
NSAttributedString(string: "수정 후", attributes: labelAttributes).draw(
  in: NSRect(x: implementationOrigin.x, y: labelY, width: implementationSize.width, height: 24)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("could not encode comparison image\n", stderr)
  exit(70)
}

try FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
