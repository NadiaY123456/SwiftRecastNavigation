// SPDX-License-Identifier: MIT
//
//  SplatMeshGenerator.swift
//  SwiftRecastNavigation
//

// Uses SimplifySwift (MIT) for polyline simplification:
// https://github.com/tomislav/Simplify-Swift


import CoreImage
import iTriangle
import simd
import SimplifySwift
import Vision

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: – Public entry point ----------------------------------------------------

public struct SplatMeshGenerator {
    public enum Channel: String, Codable {
        case red
        case green
        case blue
        case alpha
        case grayscale
    }

    /// Output edges will be **≤** this length in image-space points.
    public let maxEdgeLength: CGFloat
    /// Douglas-Peucker tolerance expressed as a fraction of the *shorter* image side.
    public let simplificationTolerance: CGFloat
    /// Optional manual threshold in [0 … 1]; `nil` → Otsu.
    public let threshold: Float?
    /// Which channel to use for mesh generation.
    public let channel: Channel
    /// `nil` → auto; `false` → detect *bright* shapes; `true` → detect *dark* shapes.
    public let invertMask: Bool?
    /// Radius (pixels) for the dilate → erode "closing" operation; 0 = skip.
    public let morphologyRadius: Int
    /// Fraction of `maxEdgeLength` to use for interior grid spacing.
    public let interiorSpacingFactor: CGFloat
    /// Whether to print debug statements
    public let debugPrint: Bool

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    public init(
        maxEdgeLength: CGFloat,
        simplificationTolerance: CGFloat = 0.005,
        threshold: Float? = nil, // nil → Otsu
        channel: Channel = .grayscale,
        invertMask: Bool? = nil, // nil → auto (old default)
        morphologyRadius: Int = 2,
        interiorSpacingFactor: CGFloat = 0.8,
        debugPrint: Bool = false

    ) {
        self.maxEdgeLength = maxEdgeLength
        self.simplificationTolerance = simplificationTolerance
        self.threshold = threshold
        self.channel = channel
        self.invertMask = invertMask
        self.morphologyRadius = morphologyRadius
        self.interiorSpacingFactor = interiorSpacingFactor
        self.debugPrint = debugPrint
    }

    // MARK: – High-level pipeline (async/await) ---------------------------------

    /// Generate a 2-D triangle mesh from an alpha mask.
    ///
    /// The routine:
    /// 1. Builds a binary mask from `ciImage`
    /// 2. Extracts the top-level contours (outer rings + one-level holes)
    /// 3. Runs constrained-Delaunay triangulation with iTriangle
    /// 4. Returns GPU-ready vertex & index buffers
    public func mesh(from ciImage: CIImage,
                     imageSize: CGSize,
                     debugURL: URL? = nil) async throws -> MeshResult2D
    {
        // 1. Vision –> binary mask
        let mask = try await createBinaryMask(from: ciImage, debugURL: debugURL)

        // 2. Vision –> contour tree (top-level only)
        let rootContours = try await detectContours(in: mask)

        var vertices: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        // 3. Walk every outer ring and its direct holes
        for (contourIndex, outerContour) in rootContours.enumerated() {
            if debugPrint {
                print("\n[DEBUG] ⇢ Contour \(contourIndex) – outer \(outerContour.pointCount) pts, \(outerContour.childContours.count) holes")
            }

            // a. Flatten → simplify → resample outer ring
            let outerRing = resample(
                points: flattenSingleContour(outerContour, imageSize: imageSize)
                    .simplified(tolerance: simplificationTolerance
                        * min(imageSize.width, imageSize.height)))

            guard outerRing.count >= 3 else { continue }

            // b. Same pipeline for direct-child holes
            let holeRings: [[CGPoint]] = outerContour.childContours.compactMap { hole in
                let simplified = flattenSingleContour(hole, imageSize: imageSize)
                    .simplified(tolerance: simplificationTolerance
                        * min(imageSize.width, imageSize.height))
                return simplified.count >= 3 ? resample(points: simplified) : nil
            }

            // c. Robust constrained-Delaunay triangulation (iTriangle)
            let (localVertices, localIndices) = triangulateITriangle(
                outerRing: outerRing,
                holeRings: holeRings)

            guard !localIndices.isEmpty else {
                if debugPrint { print("[DEBUG]    ⤺  iTriangle produced 0 triangles – skipping") }
                continue
            }

            // d. Stitch local mesh into global buffers
            let indexOffset = UInt32(vertices.count)
            vertices += localVertices.map { SIMD2(Float($0.x), Float($0.y)) }
            indices += localIndices.map { $0 + indexOffset }

            if debugPrint {
                print("[DEBUG]    ➜  kept \(localVertices.count) vertices, \(localIndices.count / 3) triangles")
            }
        }

        if debugPrint {
            print("[DEBUG] FINAL: \(vertices.count) vertices, \(indices.count / 3) triangles")
        }

        return MeshResult2D(vertices: vertices,
                            indices: indices,
                            imageSize: imageSize)
    }

    /// Generate mesh from a CGImage
    public func mesh(from cgImage: CGImage,
                     debugURL: URL? = nil) async throws -> MeshResult2D
    {
        let ciImage = CIImage(cgImage: cgImage)
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        return try await mesh(from: ciImage, imageSize: size, debugURL: debugURL)
    }

    // MARK: – Step 1: Channel isolation → threshold → morphology -----------------

    private func createBinaryMask(from ci: CIImage,
                                  debugURL: URL? = nil) async throws -> CIImage
    {
        if debugPrint {
            print("[DEBUG] Input CIImage extent: \(ci.extent)")
        }

        // (a) Extract requested channel
        var channelImage: CIImage
        switch channel {
        case .red:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .green:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .blue:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .alpha:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .grayscale:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.7152, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }

        if debugPrint {
            print("[DEBUG] Channel image extent after extraction: \(channelImage.extent)")
        }
        // Test: Ensure extent is not infinite
        if channelImage.extent.isInfinite {
            if debugPrint {
                print("[DEBUG] WARNING: Channel image has infinite extent, cropping...")
            }
            channelImage = channelImage.cropped(to: ci.extent)
        }

        // (c) Threshold
        let cutOff: Float = {
            if let manual = threshold {
                return manual
            }

            // Try Otsu, but with fallback
            if let otsu = try? computeOtsuThreshold(for: channelImage), otsu > 0.01 && otsu < 0.99 {
                return otsu
            } else {
                if debugPrint {
                    print("[DEBUG] Otsu threshold failed or returned extreme value, using fallback 0.5")
                }
                return 0.5 // Reasonable fallback
            }
        }()

        if debugPrint {
            print("[DEBUG] Using threshold: \(cutOff)")
        }

        // Create threshold filter
        guard let threshFilter = CIFilter(name: "CIColorThreshold") else {
            if debugPrint {
                print("[DEBUG] Failed to create CIColorThreshold filter")
            }
            throw MeshError.invalidImage
        }

        threshFilter.setValue(channelImage, forKey: kCIInputImageKey)
        threshFilter.setValue(cutOff, forKey: "inputThreshold")

        guard var mask = threshFilter.outputImage else {
            if debugPrint {
                print("[DEBUG] CIColorThreshold produced nil output")
            }
            throw MeshError.invalidImage
        }

        if debugPrint {
            print("[DEBUG] Mask extent after threshold: \(mask.extent)")
        }

        // (d) Inversion
        let shouldInvert: Bool = {
            if let explicit = invertMask {
                // Direct mapping - no negation!
                // invertMask = true means "invert the mask"
                // invertMask = false means "don't invert the mask"
                return explicit
            }
            // Auto mode: don't invert by default
            return false
        }()

        if debugPrint {
            print("[DEBUG] Should invert: \(shouldInvert)")
        }

        if shouldInvert {
            guard let invertFilter = CIFilter(name: "CIColorInvert") else {
                if debugPrint {
                    print("[DEBUG] Failed to create CIColorInvert filter")
                }
                throw MeshError.invalidImage
            }
            invertFilter.setValue(mask, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else {
                if debugPrint {
                    print("[DEBUG] CIColorInvert produced nil output")
                }
                throw MeshError.invalidImage
            }
            mask = inverted
            if debugPrint {
                print("[DEBUG] Mask extent after inversion: \(mask.extent)")
            }
        }

        // (e) Morphology
        if morphologyRadius > 0 {
            if debugPrint {
                print("[DEBUG] Applying morphology with radius: \(morphologyRadius)")
            }

            // Dilate
            guard let dilateFilter = CIFilter(name: "CIMorphologyRectangleMaximum") else {
                if debugPrint {
                    print("[DEBUG] Failed to create dilate filter")
                }
                throw MeshError.invalidImage
            }
            dilateFilter.setValue(mask, forKey: kCIInputImageKey)
            dilateFilter.setValue(morphologyRadius, forKey: "inputWidth")
            dilateFilter.setValue(morphologyRadius, forKey: "inputHeight")

            guard let dilated = dilateFilter.outputImage else {
                if debugPrint {
                    print("[DEBUG] Dilate filter produced nil output")
                }
                throw MeshError.invalidImage
            }

            // Erode
            guard let erodeFilter = CIFilter(name: "CIMorphologyRectangleMinimum") else {
                if debugPrint {
                    print("[DEBUG] Failed to create erode filter")
                }
                throw MeshError.invalidImage
            }
            erodeFilter.setValue(dilated, forKey: kCIInputImageKey)
            erodeFilter.setValue(morphologyRadius, forKey: "inputWidth")
            erodeFilter.setValue(morphologyRadius, forKey: "inputHeight")

            guard let eroded = erodeFilter.outputImage else {
                if debugPrint {
                    print("[DEBUG] Erode filter produced nil output")
                }
                throw MeshError.invalidImage
            }

            mask = eroded
            if debugPrint {
                print("[DEBUG] Mask extent after morphology: \(mask.extent)")
            }
        }

        // Final extent check
        if mask.extent.isInfinite {
            if debugPrint {
                print("[DEBUG] Final mask has infinite extent, cropping to original bounds")
            }
            mask = mask.cropped(to: ci.extent)
        }

        if debugPrint {
            print("[DEBUG] Final mask extent: \(mask.extent)")
        }

        // Verify we can create a CGImage (this is what Vision will need)
        if debugPrint {
            if let testCG = ciContext.createCGImage(mask, from: mask.extent) {
                print("[DEBUG] Successfully created test CGImage: \(testCG.width)x\(testCG.height)")
            } else {
                print("[DEBUG] WARNING: Cannot create CGImage from mask!")
            }
        }

        // ----- Save debug image if requested ----------------------------------
        if let url = debugURL,
           let cg = ciContext.createCGImage(mask, from: mask.extent)
        {
            try saveCGImage(cg, to: url)
        }
        // --------------------------------------------------------------------------

        return mask
    }

    // MARK: – Step 2: Contour detection (Vision) ----------------------------------

    private func detectContours(in mask: CIImage) async throws -> [VNContour] {
        if debugPrint {
            print("[DEBUG] Creating VNImageRequestHandler...")
        }

        guard let cgImage = ciContext.createCGImage(mask, from: mask.extent) else {
            throw MeshError.invalidImage
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectContoursRequest()
        request.maximumImageDimension = 1024 // keep or tweak
        request.detectsDarkOnLight = false // black-on-white mask

        try handler.perform([request])
        guard let obs = request.results?.first as? VNContoursObservation else {
            throw MeshError.noContours
        }

        if debugPrint {
            print("[DEBUG] Contours: total \(obs.contourCount)")
        }

        let realContours = obs.topLevelContours
        if debugPrint {
            print("[DEBUG] Returning \(realContours.count) real contours")
        }

        return realContours
    }

    // MARK: – Geometry helpers --------------------------------------------------

    private func flattenSingleContour(_ contour: VNContour, imageSize: CGSize) -> [CGPoint] {
        contour.normalizedPoints.map { p in
            CGPoint(x: CGFloat(p.x) * imageSize.width,
                    y: (1 - CGFloat(p.y)) * imageSize.height)
        }
    }

    private func resample(points: [CGPoint]) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        var out: [CGPoint] = []

        for (i, a) in points.enumerated() {
            let b = points[(i + 1) % points.count]
            out.append(a)

            let len = hypot(b.x - a.x, b.y - a.y)
            if len > maxEdgeLength {
                let pieces = Int(ceil(len / maxEdgeLength))
                for j in 1 ..< pieces {
                    let t = CGFloat(j) / CGFloat(pieces)
                    out.append(CGPoint(x: a.x + (b.x - a.x) * t,
                                       y: a.y + (b.y - a.y) * t))
                }
            }
        }
        return out
    }

    // MARK: – Robust triangulation helper (iTriangle) -------------------------

    /// Runs iTriangle’s constrained-Delaunay triangulation on a polygon
    /// with optional holes and converts its Int indices → UInt32.
    private func triangulateITriangle(outerRing: [CGPoint],
                                      holeRings: [[CGPoint]])
        -> (vertices: [CGPoint], indices: [UInt32])
    {
        // iTriangle expects [outerRing, hole1, hole2, …]
        let polygonWithHoles: [[CGPoint]] = [outerRing] + holeRings

        // One-liner: robust CDT that preserves every segment
        let triangulation = polygonWithHoles.triangulate()

        // Convert Int → UInt32 once, here
        let indicesUInt32 = triangulation.indices.map(UInt32.init)

        return (triangulation.points, indicesUInt32)
    }

    // MARK: – Otsu threshold ----------------------------------------------------

    private func computeOtsuThreshold(for singleChannel: CIImage) throws -> Float {
        let binCount = 256
        let histogramImage = singleChannel.applyingFilter(
            "CIAreaHistogram",
            parameters: [
                kCIInputExtentKey: CIVector(cgRect: singleChannel.extent),
                "inputCount": binCount,
                "inputScale": 1
            ])

        var rawBins = [UInt32](repeating: 0, count: binCount)
        ciContext.render(
            histogramImage,
            toBitmap: &rawBins,
            rowBytes: MemoryLayout<UInt32>.size * binCount,
            bounds: CGRect(x: 0, y: 0, width: binCount, height: 1),
            format: .RGBA8,
            colorSpace: nil)

        // The histogram might be in any channel, not just red
        // Try all channels and use the one with data
        var counts: [Float] = []

        // Check each channel
        for shift in [0, 8, 16, 24] {
            let channelCounts = rawBins.map { Float(($0 >> shift) & 0xFF) }
            let total = channelCounts.reduce(0, +)
            if total > 0 {
                counts = channelCounts
                if debugPrint {
                    print("[DEBUG] Found histogram data in channel shift \(shift), total: \(total)")
                }
                break
            }
        }

        let totalPixels = counts.reduce(0, +)
        guard totalPixels > 0 else {
            if debugPrint {
                print("[DEBUG] No histogram data found!")
            }
            return 0.5
        }

        // Standard Otsu algorithm
        var sumAll: Float = 0
        for (i, c) in counts.enumerated() {
            sumAll += c * Float(i)
        }

        var sumB: Float = 0
        var wB: Float = 0
        var maxVar: Float = -1
        var bestK = 0

        for k in 0 ..< binCount {
            wB += counts[k]
            if wB == 0 { continue }

            let wF = totalPixels - wB
            if wF == 0 { break }

            sumB += counts[k] * Float(k)
            let mB = sumB / wB
            let mF = (sumAll - sumB) / wF
            let between = wB * wF * pow(mB - mF, 2)

            if between > maxVar {
                maxVar = between
                bestK = k
            }
        }

        return Float(bestK) / Float(binCount - 1)
    }

    // MARK: – Image saving helper ----------------------------------------------------

    private func saveCGImage(_ cgImage: CGImage, to url: URL) throws {
        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        if let tiffData = nsImage.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:])
        {
            try pngData.write(to: url, options: .atomic)
            if debugPrint {
                print("[DEBUG] Wrote threshold mask → \(url.path)")
            }
        }
        #else
        let uiImage = UIImage(cgImage: cgImage)
        if let pngData = uiImage.pngData() {
            try pngData.write(to: url, options: .atomic)
            if debugPrint {
                print("[DEBUG] Wrote threshold mask → \(url.path)")
            }
        }
        #endif
    }
}

// MARK: – Supporting types ------------------------------------------------------

private enum MeshError: Error { case invalidImage, noContours }

public struct MeshResult2D {
    public let vertices: [SIMD2<Float>]
    public let indices: [UInt32]
    public let imageSize: CGSize
}

// MARK: – Simplification helper -------------------------------------------------

private extension Array where Element == CGPoint {
    func simplified(tolerance: CGFloat) -> [CGPoint] {
//        SwiftSimplify.simplify(self, tolerance: Float(tolerance))
        let simplifiedPoints = Simplify.simplify(self, tolerance: Float(tolerance))
        return Array(simplifiedPoints)
    }
}

// MARK: – Platform-specific convenience extensions -----------------------------

#if os(macOS)
public extension SplatMeshGenerator {
    func mesh(from image: NSImage, debugURL: URL? = nil) async throws -> MeshResult2D {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ciImage = CIImage(bitmapImageRep: bitmap)
        else {
            throw MeshError.invalidImage
        }
        return try await mesh(from: ciImage, imageSize: image.size, debugURL: debugURL)
    }
}
#else
public extension SplatMeshGenerator {
    func mesh(from image: UIImage, debugURL: URL? = nil) async throws -> MeshResult2D {
        guard let ciImage = CIImage(image: image) else {
            throw MeshError.invalidImage
        }
        return try await mesh(from: ciImage, imageSize: image.size, debugURL: debugURL)
    }
}
#endif
