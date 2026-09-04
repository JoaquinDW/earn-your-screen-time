import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The ground every screen sits on, with a grain that keeps large flat areas from banding.
///
/// v6's ground is near-black, so the grain now *lifts* instead of multiplying: on a dark screen a
/// multiply blend is invisible, while the smooth gradients the design leans on band visibly
/// without a little noise under them.
///
/// The grain is generated once at launch and tiled; it is decorative, so it is hidden from
/// accessibility and never intercepts touches.
struct PaperBackground: View {
    var color: Color = Theme.background

    var body: some View {
        color
            .overlay(GrainTexture())
            .ignoresSafeArea()
    }
}

struct GrainTexture: View {
    var opacity: Double = 0.05

    var body: some View {
        GeometryReader { geometry in
            if let grain = GrainImage.shared {
                Image(uiImage: grain)
                    .resizable(resizingMode: .tile)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blendMode(.plusLighter)
                    .opacity(opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum GrainImage {
    /// One 160pt tile of desaturated noise, rendered once. `nil` if Core Image is unavailable,
    /// in which case the background is simply flat.
    static let shared: UIImage? = {
        let side: CGFloat = 160
        let extent = CGRect(x: 0, y: 0, width: side, height: side)

        let noise = CIFilter.randomGenerator().outputImage
        guard let noise else { return nil }

        let mono = CIFilter.colorControls()
        mono.inputImage = noise
        mono.saturation = 0
        mono.contrast = 0.55
        mono.brightness = 0.42
        guard let output = mono.outputImage?.cropped(to: extent) else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }()
}

extension View {
    /// Puts the paper ground behind a screen.
    func paperBackground(_ color: Color = Theme.background) -> some View {
        background(PaperBackground(color: color))
    }
}
