#!/usr/bin/env swift
//
// Lifts a painted Guardian off its plate and writes a transparent PNG, cropped to the figure.
//
//     swift scripts/guardian-cutout.swift <painting.png> <guardian-resting@2x.png>
//
// Artboards are often painted on a dark ground, and the app's is warm ivory. A luminance key
// would eat the ink and the dark half of the wings, so this uses Vision's foreground-instance
// mask instead: it keeps every pigment inside the figure's silhouette and drops the plate,
// including the halo the painting sits in — the app draws its own light behind the figure.
//
// Requires macOS 14+.

import AppKit
import CoreImage
import Vision

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(
        "usage: guardian-cutout <input.png> <output.png>\n".data(using: .utf8)!
    )
    exit(1)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CIImage(contentsOf: inputURL) else {
    FileHandle.standardError.write("cannot read \(inputURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let handler = VNImageRequestHandler(ciImage: source, options: [:])
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])

guard let observation = request.results?.first else {
    FileHandle.standardError.write("no figure found in the painting\n".data(using: .utf8)!)
    exit(2)
}

let masked = CIImage(
    cvPixelBuffer: try observation.generateMaskedImage(
        ofInstances: observation.allInstances,
        from: handler,
        croppedToInstancesExtent: true
    )
)

guard let png = CIContext().pngRepresentation(
    of: masked,
    format: .RGBA8,
    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
) else {
    FileHandle.standardError.write("cannot encode png\n".data(using: .utf8)!)
    exit(1)
}

try png.write(to: outputURL)
print("wrote \(Int(masked.extent.width))×\(Int(masked.extent.height)) → \(outputURL.path)")
