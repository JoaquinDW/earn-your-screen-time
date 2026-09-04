#!/usr/bin/env swift
//
// Turns a supplied logo PNG into the two shapes the project needs.
//
//     swift scripts/make-app-icon.swift <logo.png> <AppIcon.png> <app-logo.png>
//
// Brand artwork usually arrives already presented: rounded corners, a drop shadow, and a
// transparent margin around it. An iOS app icon must be the opposite — a full-bleed, fully
// opaque 1024×1024 square. Shipping the presented file directly gets the icon rejected for
// having an alpha channel, and iOS would round the corners a second time over the ones baked
// into the art, leaving a pale ring and a shadow smear inside the mask.
//
// So this does three things:
//   1. Crops to the icon body by its own alpha, which drops the soft shadow and the margin.
//   2. Fills the transparent rounded corners with the colour the artwork already uses at its
//      edge, so the square reads as solid black and iOS's mask lands on nothing.
//   3. Writes a 1024×1024 PNG with no alpha channel.
//
// The second output is the in-app logo, where the rounded presentation *is* the point, so it
// keeps its alpha — only downsampled, because nothing on a phone draws a logo at 1254pt.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write(
        Data("usage: make-app-icon <logo.png> <AppIcon.png> <app-logo.png>\n".utf8)
    )
    exit(1)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let iconURL = URL(fileURLWithPath: arguments[2])
let logoURL = URL(fileURLWithPath: arguments[3])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("could not read \(inputURL.path)\n".utf8))
    exit(1)
}

let width = image.width
let height = image.height

// MARK: - Read the pixels once, premultiplied-last so alpha is directly comparable.

var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard
    let readContext = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("could not create a reading context\n".utf8))
    exit(1)
}
readContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

// MARK: - Crop to the icon body
//
// The shadow is partially transparent and the body is not, so a high alpha threshold separates
// them without needing to know how the file was exported.

let solid: UInt8 = 250
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where alpha(x, y) >= solid {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}

guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write(Data("\(inputURL.lastPathComponent) has no opaque pixels\n".utf8))
    exit(1)
}

// Square it around the centre of what was found, so a logo that is a pixel or two off-square
// is not stretched.
let bodyWidth = maxX - minX + 1
let bodyHeight = maxY - minY + 1
let side = max(bodyWidth, bodyHeight)
let originX = max(0, min(width - side, minX - (side - bodyWidth) / 2))
let originY = max(0, min(height - side, minY - (side - bodyHeight) / 2))
let cropRect = CGRect(x: originX, y: originY, width: side, height: side)

guard let body = image.cropping(to: cropRect) else {
    FileHandle.standardError.write(Data("could not crop the icon body\n".utf8))
    exit(1)
}

// MARK: - The colour behind the corners
//
// Sampled from the middle of the body's top edge, a few pixels in: that is inside the artwork
// but outside the rounded corner, so it is whatever the art fades to at its own boundary.

let sampleX = originX + side / 2
let sampleY = originY + min(height - 1, 6)
let sampleIndex = (sampleY * width + sampleX) * 4
let corner = CGColor(
    srgbRed: CGFloat(pixels[sampleIndex]) / 255,
    green: CGFloat(pixels[sampleIndex + 1]) / 255,
    blue: CGFloat(pixels[sampleIndex + 2]) / 255,
    alpha: 1
)

// MARK: - Write the opaque 1024 icon

let iconSide = 1_024
guard
    let iconContext = CGContext(
        data: nil,
        width: iconSide,
        height: iconSide,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        // `noneSkipLast` is what drops the alpha channel from the written file.
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("could not create the icon context\n".utf8))
    exit(1)
}

iconContext.interpolationQuality = .high
let iconRect = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
iconContext.setFillColor(corner)
iconContext.fill(iconRect)
iconContext.draw(body, in: iconRect)

guard
    let icon = iconContext.makeImage(),
    let iconDestination = CGImageDestinationCreateWithURL(
        iconURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    FileHandle.standardError.write(Data("could not write \(iconURL.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(iconDestination, icon, nil)
guard CGImageDestinationFinalize(iconDestination) else {
    FileHandle.standardError.write(Data("could not finalize \(iconURL.path)\n".utf8))
    exit(1)
}

// MARK: - The in-app logo: same presentation, transparent, and small enough to ship

let logoSide = 512
guard
    let logoContext = CGContext(
        data: nil,
        width: logoSide,
        height: logoSide,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("could not create the logo context\n".utf8))
    exit(1)
}

logoContext.interpolationQuality = .high
// Drawn from the full source, shadow and margin included: that framing is the logo.
logoContext.draw(image, in: CGRect(x: 0, y: 0, width: logoSide, height: logoSide))

guard
    let logo = logoContext.makeImage(),
    let logoDestination = CGImageDestinationCreateWithURL(
        logoURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    FileHandle.standardError.write(Data("could not write \(logoURL.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(logoDestination, logo, nil)
guard CGImageDestinationFinalize(logoDestination) else {
    FileHandle.standardError.write(Data("could not finalize \(logoURL.path)\n".utf8))
    exit(1)
}

print("""
icon body \(bodyWidth)×\(bodyHeight) at (\(minX), \(minY))
corner fill #\(String(format: "%02X%02X%02X", pixels[sampleIndex], pixels[sampleIndex + 1], pixels[sampleIndex + 2]))
wrote \(iconURL.lastPathComponent) (\(iconSide)×\(iconSide), no alpha)
wrote \(logoURL.lastPathComponent) (\(logoSide)×\(logoSide), alpha kept)
""")
