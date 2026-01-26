#if canImport(AppKit)
import AppKit

/// Parser for Windows BMP files
/// Handles various BMP formats including older OS/2 and Windows 3.x formats
public class BMPParser {
    
    /// Parse BMP data into an NSImage
    /// - Parameter data: Raw BMP file data
    /// - Returns: Parsed NSImage or nil if parsing fails
    public static func parse(data: Data) -> NSImage? {
        guard data.count >= 54 else { return nil }
        
        // Check BMP signature ("BM")
        guard data[0] == 0x42 && data[1] == 0x4D else { return nil }
        
        // Read header information
        let pixelDataOffset = readUInt32(data, offset: 10)
        let headerSize = readUInt32(data, offset: 14)
        
        var width: Int
        var height: Int
        var bitsPerPixel: Int
        var compression: UInt32 = 0
        var topDown = false
        
        if headerSize == 12 {
            // OS/2 1.x BITMAPCOREHEADER
            width = Int(readUInt16(data, offset: 18))
            height = Int(readUInt16(data, offset: 20))
            bitsPerPixel = Int(readUInt16(data, offset: 24))
        } else {
            // Windows BITMAPINFOHEADER or later
            width = Int(readInt32(data, offset: 18))
            let rawHeight = readInt32(data, offset: 22)
            height = abs(Int(rawHeight))
            topDown = rawHeight < 0
            bitsPerPixel = Int(readUInt16(data, offset: 28))
            compression = readUInt32(data, offset: 30)
        }
        
        guard width > 0 && height > 0 else { return nil }
        
        // Only support uncompressed (0) and RLE8 (1) and RLE4 (2) for now
        guard compression <= 2 else {
            return nil
        }
        
        // Calculate row padding (rows are aligned to 4 bytes)
        let bytesPerPixel = bitsPerPixel / 8
        let rowSizeUnpadded = width * max(1, bytesPerPixel)
        let rowSize = (rowSizeUnpadded + 3) & ~3
        
        // Create pixel buffer
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        
        // Read color palette if needed
        var palette: [[UInt8]] = []
        if bitsPerPixel <= 8 {
            let paletteOffset = 14 + Int(headerSize)
            let colorCount = 1 << bitsPerPixel
            let colorSize = headerSize == 12 ? 3 : 4  // OS/2 uses 3, Windows uses 4
            
            for i in 0..<colorCount {
                let offset = paletteOffset + i * colorSize
                if offset + 2 < data.count {
                    let b = data[offset]
                    let g = data[offset + 1]
                    let r = data[offset + 2]
                    palette.append([r, g, b, 255])
                }
            }
        }
        
        // Parse pixel data
        let pixelOffset = Int(pixelDataOffset)
        
        switch bitsPerPixel {
        case 1:
            parse1Bit(data: data, offset: pixelOffset, width: width, height: height,
                      rowSize: rowSize, palette: palette, pixels: &pixels, topDown: topDown)
        case 4:
            if compression == 2 {
                parseRLE4(data: data, offset: pixelOffset, width: width, height: height,
                          palette: palette, pixels: &pixels)
            } else {
                parse4Bit(data: data, offset: pixelOffset, width: width, height: height,
                          rowSize: rowSize, palette: palette, pixels: &pixels, topDown: topDown)
            }
        case 8:
            if compression == 1 {
                parseRLE8(data: data, offset: pixelOffset, width: width, height: height,
                          palette: palette, pixels: &pixels)
            } else {
                parse8Bit(data: data, offset: pixelOffset, width: width, height: height,
                          rowSize: rowSize, palette: palette, pixels: &pixels, topDown: topDown)
            }
        case 24:
            parse24Bit(data: data, offset: pixelOffset, width: width, height: height,
                       rowSize: rowSize, pixels: &pixels, topDown: topDown)
        case 32:
            parse32Bit(data: data, offset: pixelOffset, width: width, height: height,
                       rowSize: rowSize, pixels: &pixels, topDown: topDown)
        default:
            return nil
        }
        
        // Handle transparency (magenta = transparent in Winamp skins)
        applyMagentaTransparency(&pixels, width: width, height: height)
        
        // Create NSImage from pixel data
        return createImage(from: pixels, width: width, height: height)
    }
    
    // MARK: - Private Parsing Methods
    
    private static func parse1Bit(data: Data, offset: Int, width: Int, height: Int,
                                   rowSize: Int, palette: [[UInt8]], pixels: inout [UInt8], topDown: Bool) {
        for y in 0..<height {
            let srcY = topDown ? y : (height - 1 - y)
            let rowOffset = offset + srcY * rowSize
            
            for x in 0..<width {
                let byteIndex = rowOffset + x / 8
                guard byteIndex < data.count else { continue }
                
                let bit = 7 - (x % 8)
                let colorIndex = Int((data[byteIndex] >> bit) & 1)
                
                let dstIndex = (y * width + x) * 4
                if colorIndex < palette.count {
                    pixels[dstIndex] = palette[colorIndex][0]
                    pixels[dstIndex + 1] = palette[colorIndex][1]
                    pixels[dstIndex + 2] = palette[colorIndex][2]
                    pixels[dstIndex + 3] = palette[colorIndex][3]
                }
            }
        }
    }
    
    private static func parse4Bit(data: Data, offset: Int, width: Int, height: Int,
                                   rowSize: Int, palette: [[UInt8]], pixels: inout [UInt8], topDown: Bool) {
        for y in 0..<height {
            let srcY = topDown ? y : (height - 1 - y)
            let rowOffset = offset + srcY * rowSize
            
            for x in 0..<width {
                let byteIndex = rowOffset + x / 2
                guard byteIndex < data.count else { continue }
                
                let colorIndex: Int
                if x % 2 == 0 {
                    colorIndex = Int((data[byteIndex] >> 4) & 0x0F)
                } else {
                    colorIndex = Int(data[byteIndex] & 0x0F)
                }
                
                let dstIndex = (y * width + x) * 4
                if colorIndex < palette.count {
                    pixels[dstIndex] = palette[colorIndex][0]
                    pixels[dstIndex + 1] = palette[colorIndex][1]
                    pixels[dstIndex + 2] = palette[colorIndex][2]
                    pixels[dstIndex + 3] = palette[colorIndex][3]
                }
            }
        }
    }
    
    private static func parse8Bit(data: Data, offset: Int, width: Int, height: Int,
                                   rowSize: Int, palette: [[UInt8]], pixels: inout [UInt8], topDown: Bool) {
        for y in 0..<height {
            let srcY = topDown ? y : (height - 1 - y)
            let rowOffset = offset + srcY * rowSize
            
            for x in 0..<width {
                let byteIndex = rowOffset + x
                guard byteIndex < data.count else { continue }
                
                let colorIndex = Int(data[byteIndex])
                let dstIndex = (y * width + x) * 4
                
                if colorIndex < palette.count {
                    pixels[dstIndex] = palette[colorIndex][0]
                    pixels[dstIndex + 1] = palette[colorIndex][1]
                    pixels[dstIndex + 2] = palette[colorIndex][2]
                    pixels[dstIndex + 3] = palette[colorIndex][3]
                }
            }
        }
    }
    
    private static func parse24Bit(data: Data, offset: Int, width: Int, height: Int,
                                    rowSize: Int, pixels: inout [UInt8], topDown: Bool) {
        for y in 0..<height {
            let srcY = topDown ? y : (height - 1 - y)
            let rowOffset = offset + srcY * rowSize
            
            for x in 0..<width {
                let srcIndex = rowOffset + x * 3
                guard srcIndex + 2 < data.count else { continue }
                
                let dstIndex = (y * width + x) * 4
                // BMP stores as BGR, convert to RGBA
                pixels[dstIndex] = data[srcIndex + 2]      // R
                pixels[dstIndex + 1] = data[srcIndex + 1]  // G
                pixels[dstIndex + 2] = data[srcIndex]      // B
                pixels[dstIndex + 3] = 255                 // A
            }
        }
    }
    
    private static func parse32Bit(data: Data, offset: Int, width: Int, height: Int,
                                    rowSize: Int, pixels: inout [UInt8], topDown: Bool) {
        for y in 0..<height {
            let srcY = topDown ? y : (height - 1 - y)
            let rowOffset = offset + srcY * rowSize
            
            for x in 0..<width {
                let srcIndex = rowOffset + x * 4
                guard srcIndex + 3 < data.count else { continue }
                
                let dstIndex = (y * width + x) * 4
                // BMP stores as BGRA, convert to RGBA
                pixels[dstIndex] = data[srcIndex + 2]      // R
                pixels[dstIndex + 1] = data[srcIndex + 1]  // G
                pixels[dstIndex + 2] = data[srcIndex]      // B
                pixels[dstIndex + 3] = data[srcIndex + 3]  // A
            }
        }
    }
    
    private static func parseRLE8(data: Data, offset: Int, width: Int, height: Int,
                                   palette: [[UInt8]], pixels: inout [UInt8]) {
        var x = 0
        var y = height - 1
        var i = offset
        
        while i < data.count - 1 && y >= 0 {
            let count = Int(data[i])
            let value = Int(data[i + 1])
            i += 2
            
            if count == 0 {
                switch value {
                case 0:
                    x = 0
                    y -= 1
                case 1:
                    return
                case 2:
                    if i + 1 < data.count {
                        x += Int(data[i])
                        y -= Int(data[i + 1])
                        i += 2
                    }
                default:
                    for _ in 0..<value {
                        if i < data.count && x < width && y >= 0 {
                            let colorIndex = Int(data[i])
                            let dstIndex = (y * width + x) * 4
                            if colorIndex < palette.count {
                                pixels[dstIndex] = palette[colorIndex][0]
                                pixels[dstIndex + 1] = palette[colorIndex][1]
                                pixels[dstIndex + 2] = palette[colorIndex][2]
                                pixels[dstIndex + 3] = palette[colorIndex][3]
                            }
                            x += 1
                            i += 1
                        }
                    }
                    if value % 2 != 0 {
                        i += 1
                    }
                }
            } else {
                for _ in 0..<count {
                    if x < width && y >= 0 {
                        let dstIndex = (y * width + x) * 4
                        if value < palette.count {
                            pixels[dstIndex] = palette[value][0]
                            pixels[dstIndex + 1] = palette[value][1]
                            pixels[dstIndex + 2] = palette[value][2]
                            pixels[dstIndex + 3] = palette[value][3]
                        }
                        x += 1
                    }
                }
            }
        }
    }
    
    private static func parseRLE4(data: Data, offset: Int, width: Int, height: Int,
                                   palette: [[UInt8]], pixels: inout [UInt8]) {
        var x = 0
        var y = height - 1
        var i = offset
        
        while i < data.count - 1 && y >= 0 {
            let count = Int(data[i])
            let value = Int(data[i + 1])
            i += 2
            
            if count == 0 {
                switch value {
                case 0:
                    x = 0
                    y -= 1
                case 1:
                    return
                case 2:
                    if i + 1 < data.count {
                        x += Int(data[i])
                        y -= Int(data[i + 1])
                        i += 2
                    }
                default:
                    for j in 0..<value {
                        if x < width && y >= 0 {
                            let colorIndex: Int
                            if j % 2 == 0 {
                                colorIndex = Int((data[i + j/2] >> 4) & 0x0F)
                            } else {
                                colorIndex = Int(data[i + j/2] & 0x0F)
                            }
                            let dstIndex = (y * width + x) * 4
                            if colorIndex < palette.count {
                                pixels[dstIndex] = palette[colorIndex][0]
                                pixels[dstIndex + 1] = palette[colorIndex][1]
                                pixels[dstIndex + 2] = palette[colorIndex][2]
                                pixels[dstIndex + 3] = palette[colorIndex][3]
                            }
                            x += 1
                        }
                    }
                    i += ((value + 3) / 4) * 2
                }
            } else {
                let high = (value >> 4) & 0x0F
                let low = value & 0x0F
                for j in 0..<count {
                    if x < width && y >= 0 {
                        let colorIndex = (j % 2 == 0) ? high : low
                        let dstIndex = (y * width + x) * 4
                        if colorIndex < palette.count {
                            pixels[dstIndex] = palette[colorIndex][0]
                            pixels[dstIndex + 1] = palette[colorIndex][1]
                            pixels[dstIndex + 2] = palette[colorIndex][2]
                            pixels[dstIndex + 3] = palette[colorIndex][3]
                        }
                        x += 1
                    }
                }
            }
        }
    }
    
    private static func applyMagentaTransparency(_ pixels: inout [UInt8], width: Int, height: Int) {
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixels[i] == 255 && pixels[i + 1] == 0 && pixels[i + 2] == 255 {
                    pixels[i + 3] = 0
                }
            }
        }
    }
    
    private static func createImage(from pixels: [UInt8], width: Int, height: Int) -> NSImage? {
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    
    // MARK: - Helper Methods
    
    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        return UInt32(data[offset]) |
               (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16) |
               (UInt32(data[offset + 3]) << 24)
    }
    
    private static func readInt32(_ data: Data, offset: Int) -> Int32 {
        return Int32(bitPattern: readUInt32(data, offset: offset))
    }
}
#endif
