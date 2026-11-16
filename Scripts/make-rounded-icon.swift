#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: make-rounded-icon.swift <input.png> <output.png>\n", stderr)
  exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let image = NSImage(contentsOf: inputURL), image.size == NSSize(width: 1024, height: 1024)
else {
  fputs("input must be a 1024x1024 image\n", stderr)
  exit(65)
}

guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fputs("could not allocate output bitmap\n", stderr)
  exit(70)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()

let iconBounds = NSRect(x: 2, y: 2, width: 1020, height: 1020)
NSBezierPath(roundedRect: iconBounds, xRadius: 215, yRadius: 215).addClip()
image.draw(
  in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
  from: .zero,
  operation: .sourceOver,
  fraction: 1,
  respectFlipped: true,
  hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("could not encode output PNG\n", stderr)
  exit(70)
}
try png.write(to: outputURL, options: .atomic)
