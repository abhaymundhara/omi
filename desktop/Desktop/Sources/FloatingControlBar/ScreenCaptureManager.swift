import AppKit

class ScreenCaptureManager {
    /// Returns a CGImage for the screen under the mouse cursor.
    ///
    /// **IMPORTANT — Backing Scale:** `CGDisplayCreateImage()` returns pixel data at the
    /// display's native resolution. On a Retina display (2x backing scale), the CGImage
    /// is already 2× the display's point dimensions. All subsequent scaling in
    /// `encodeJPEGThumbnail` operates on the raw pixel size, which is correct — the
    /// scaling ratio is computed from actual pixel dimensions, not points. If any future
    /// code adds a **region-of-interest crop** before the scale, it must divide the crop
    /// rect by `screen.backingScaleFactor` to avoid cropping only half the intended area.
    ///
    /// Used by PushToTalkManager for context capture and ScreenContextPipeline.
    static func captureScreenImage() -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else {
            log("ScreenCaptureManager: Screen recording permission not granted, skipping capture")
            return nil
        }

        let displayID = displayIDUnderMouse()
        guard let image = CGDisplayCreateImage(displayID) else {
            log("ScreenCaptureManager: Could not capture screen (display \(displayID))")
            return nil
        }

        return image
    }

    /// Returns a lightweight JPEG thumbnail of the screen (max 512px on longest side, quality 0.4).
    /// Used as a visual fallback for screen-aware queries. No WebP dependency.
    ///
    /// ⚠️ **OCR Warning:** This compresses to 512px 0.4 quality JPEG immediately.
    /// Running `VNRecognizeTextRequest` on the output will destroy text recognition
    /// for small IDE or terminal fonts. If OCR is needed, call `captureScreenImage()`
    /// first to get the raw CGImage at full resolution, run OCR on that, then call
    /// `encodeJPEGThumbnail()` separately for the thumbnail.
    static func captureThumbnail(square: Bool = false) -> Data? {
        guard let image = captureScreenImage() else { return nil }
        return encodeJPEGThumbnail(image, square: square)
    }

    /// Compute scaled dimensions for a JPEG thumbnail.
    /// Returns `(scaledWidth, scaledHeight, canvasWidth, canvasHeight)` where:
    /// - `scaledWidth`/`scaledHeight` are the proportional dimensions capped at `maxDimension`.
    /// - `canvasWidth`/`canvasHeight` equal `scaledWidth`/`scaledHeight` when `square` is false,
    ///    or `maxDimension` (square) when `square` is true.
    static func thumbnailDimensions(
        imageWidth: CGFloat, imageHeight: CGFloat,
        maxDimension: CGFloat = 512, square: Bool = false
    ) -> (scaledWidth: Int, scaledHeight: Int, canvasWidth: Int, canvasHeight: Int) {
        let scale = min(maxDimension / max(imageWidth, imageHeight), 1.0)
        let newWidth = Int(imageWidth * scale)
        let newHeight = Int(imageHeight * scale)

        if square && newWidth != newHeight {
            return (newWidth, newHeight, Int(maxDimension), Int(maxDimension))
        }
        return (newWidth, newHeight, newWidth, newHeight)
    }

    /// Encode a CGImage as a lightweight JPEG thumbnail (max 512px on longest side, quality 0.4).
    ///
    /// - Parameter square: If true, center-pads (letterboxes) the image to a 1:1 aspect ratio
    ///   before JPEG compression. Use this when the downstream model expects square inputs
    ///   (e.g. ViT-based vision models). Without padding, proportional scaling may cause
    ///   stretching if the model internally forces a square. Default `false`.
    ///
    /// ⚠️ **OCR Warning:** The 512px 0.4 quality JPEG is too compressed for reliable
    /// `VNRecognizeTextRequest` on small fonts. Run OCR on the raw CGImage before this.
    private static func encodeJPEGThumbnail(_ image: CGImage, square: Bool = false) -> Data? {
        let (scaledW, scaledH, canvasW, canvasH) = thumbnailDimensions(
            imageWidth: CGFloat(image.width),
            imageHeight: CGFloat(image.height),
            maxDimension: 512,
            square: square
        )

        let padToSquare = square && scaledW != scaledH

        guard let ctx = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high

        if padToSquare {
            // Fill canvas with black (letterbox bars)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
            // Center the scaled image within the canvas
            let offsetX = (CGFloat(canvasW) - CGFloat(scaledW)) / 2.0
            let offsetY = (CGFloat(canvasH) - CGFloat(scaledH)) / 2.0
            ctx.draw(image, in: CGRect(x: offsetX, y: offsetY, width: CGFloat(scaledW), height: CGFloat(scaledH)))
        } else {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(scaledW), height: CGFloat(scaledH)))
        }

        guard let resizedImage = ctx.makeImage() else { return nil }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, "public.jpeg" as CFString, 1, nil)
        else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.4]
        CGImageDestinationAddImage(dest, resizedImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        return data as Data
    }

    private static func displayIDUnderMouse() -> CGDirectDisplayID {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation),
               let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                return screenNumber
            }
        }
        return CGMainDisplayID()
    }

    /// Lightweight screen capture that writes a JPEG thumbnail to disk for tool executors.
    static func captureScreen() -> URL? {
        guard let data = captureThumbnail() else { return nil }

        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let screenshotsDirectory = documentsDirectory
            .appendingPathComponent("Omi")
            .appendingPathComponent("Screenshots")
        try? fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true, attributes: nil)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let fileURL = screenshotsDirectory.appendingPathComponent("screenshot-\(timestamp).jpg")

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            log("ScreenCaptureManager: Could not save screenshot: \(error)")
            return nil
        }
    }
}
