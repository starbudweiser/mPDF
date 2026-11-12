// mPDF — détourage automatique des images importées (sujet principal isolé par Vision, fond rendu transparent).
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum Cutout {
    static let key = "autoCutout"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }
    private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// Image détourée et recadrée sur le sujet ; l'image d'origine si elle a déjà de la transparence ou si aucun sujet n'est trouvé.
    /// Le masque Vision est resserré de quelques pixels puis adouci, et appliqué sur l'image d'origine (couleurs intactes, pas de liseré de fond).
    static func apply(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        switch cg.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: break; default: return image }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first, !obs.allInstances.isEmpty,
              let maskBuffer = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
        else { return image }

        let original = CIImage(cgImage: cg)
        let extent = original.extent
        let unit = max(min(extent.width, extent.height) / 1500, 0.6)
        var mask = CIImage(cvPixelBuffer: maskBuffer).cropped(to: extent)
        let erode = CIFilter.morphologyMinimum(); erode.inputImage = mask; erode.radius = Float(unit * 4)
        mask = (erode.outputImage ?? mask).clampedToExtent()
        let blur = CIFilter.gaussianBlur(); blur.inputImage = mask; blur.radius = Float(unit * 1.6)
        mask = (blur.outputImage ?? mask).cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = original
        blend.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        blend.maskImage = mask
        guard let composed = blend.outputImage,
              let full = context.createCGImage(composed, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!),
              let out = cropToAlpha(full) else { return image }
        let k = image.size.width / CGFloat(max(cg.width, 1))
        return NSImage(cgImage: out, size: NSSize(width: CGFloat(out.width) * k, height: CGFloat(out.height) * k))
    }

    /// Recadre sur la zone non transparente.
    private static func cropToAlpha(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 8 {
            if x < minX { minX = x }; if x > maxX { maxX = x }; if y < minY { minY = y }; maxY = y
        } }
        guard maxX >= minX, maxY >= minY else { return nil }
        return img.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
