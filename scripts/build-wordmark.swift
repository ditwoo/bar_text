#!/usr/bin/env swift
//
// Regenerate packaging/icon.svg: the rounded white card plus the `bar_text`
// wordmark, set in a pixel font.
//
//   swift scripts/build-wordmark.swift [options]
//
//     --font PATH    TTF/OTF to draw with       (packaging/fonts/Jersey15-Regular.ttf)
//     --text STR     wordmark text              (bar_text)
//     --ppem N       design size in pixels      (27)
//     --super N      supersample factor         (8)
//     --width N      target wordmark width      (716, inside the 824px card)
//     --out PATH     where to write the SVG     (packaging/icon.svg)
//     --dump         print the pixel grid to stderr
//
// `--ppem` must be the size at which one pixel of the font's own design grid
// lands on exactly one device pixel, otherwise its letterforms cannot be
// reproduced faithfully. That size is unitsPerEm / (font units per design
// pixel): for Jersey 15 that is 1350 / 50 = 27px. If you swap fonts, check the
// grid first -- a font whose outlines are not on a whole-pixel grid (Silkscreen,
// for instance, has 5-unit noise) will lose or thicken stems here, because a
// stem straddling two blocks at exactly 50% coverage wins no block at all.
// scripts/build-wordmark.swift --dump prints the grid so you can inspect it.
//
// Getting clean pixels out of Core Graphics is the whole problem here. Pixel
// fonts are drawn as axis-aligned rectangles on a fine grid, but when Core
// Graphics rasterises text it applies hinting, which snaps and widens stems at
// small sizes and mangles those rectangles (a 1px stem becomes 2px on one side
// of a glyph and 1px on the other). So instead of trusting a small render, we
// draw at `super` times the design size -- where a whole design pixel is many
// raster pixels and hinting error is proportionally tiny -- and then collapse
// each block to a single pixel by majority vote. A block that should be solid
// comes out ~100% covered and a block that should be empty ~0%, so the vote is
// unambiguous even when hinting shifts an edge by a pixel. The resulting 1-bit
// bitmap is then scaled up by an integer factor onto the 1024px canvas, so every
// pixel becomes an exact square block.
//

import CoreGraphics
import CoreText
import Foundation

// MARK: - canvas constants (macOS app-icon grid)

let canvas = 1024
let art = 824
let margin = (canvas - art) / 2
let corner: Double = 185.4

// MARK: - options

struct Options {
    var font = "packaging/fonts/Jersey15-Regular.ttf"
    var text = "bar_text"
    var ppem = 27
    var supersample = 8
    var width = 716
    var out = "packaging/icon.svg"
    var dump = false
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

var opts = Options()
var argv = Array(CommandLine.arguments.dropFirst())
while let flag = argv.first {
    argv.removeFirst()
    func next() -> String {
        guard !argv.isEmpty else { die("\(flag) requires a value") }
        return argv.removeFirst()
    }
    func nextInt() -> Int {
        let raw = next()
        guard let value = Int(raw) else { die("\(flag) expects an integer, got \(raw)") }
        return value
    }
    switch flag {
    case "--font": opts.font = next()
    case "--text": opts.text = next()
    case "--ppem": opts.ppem = nextInt()
    case "--super": opts.supersample = nextInt()
    case "--width": opts.width = nextInt()
    case "--out": opts.out = next()
    case "--dump": opts.dump = true
    case "-h", "--help":
        print("usage: swift scripts/build-wordmark.swift [--font P] [--text S] [--ppem N] [--super N] [--width N] [--out P] [--dump]")
        exit(0)
    default: die("unknown option \(flag)")
    }
}
guard opts.ppem > 0 else { die("--ppem must be positive") }
let superFactor = max(1, opts.supersample)

// MARK: - load the font straight from disk (no system install required)

let fontData: Data
do {
    fontData = try Data(contentsOf: URL(fileURLWithPath: opts.font))
} catch {
    die("cannot read \(opts.font): \(error.localizedDescription)")
}
guard let provider = CGDataProvider(data: fontData as CFData),
      let cgFont = CGFont(provider) else {
    die("\(opts.font) is not a font Core Graphics can load")
}
// Draw at the supersampled size; one design pixel is superFactor raster pixels.
let rasterPpem = CGFloat(opts.ppem * superFactor)
let ctFont = CTFontCreateWithGraphicsFont(cgFont, rasterPpem, nil, nil)
let fontName = CTFontCopyFullName(ctFont) as String

// MARK: - map characters to glyphs

let units = Array(opts.text.utf16)
var glyphs = [CGGlyph](repeating: 0, count: units.count)
var missing = ""
for (i, unit) in units.enumerated() {
    var glyph: CGGlyph = 0
    var one = unit
    if !CTFontGetGlyphsForCharacters(ctFont, &one, &glyph, 1) || glyph == 0 {
        missing += String(Character(UnicodeScalar(unit) ?? " "))
    }
    glyphs[i] = glyph
}
if !missing.isEmpty {
    die("\(fontName) has no glyph for: \(missing)")
}

var advances = [CGSize](repeating: .zero, count: glyphs.count)
CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, glyphs.count)
var boxes = [CGRect](repeating: .zero, count: glyphs.count)
CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, glyphs, &boxes, glyphs.count)

// Lay the glyphs out on whole design pixels: snap each advance at design
// resolution, then scale back up so the pen still lands on design-pixel
// boundaries in the supersampled raster.
let K = CGFloat(superFactor)
var positions: [CGPoint] = []
var penDesign = 0
for advance in advances {
    positions.append(CGPoint(x: CGFloat(penDesign) * K, y: 0))
    penDesign += Int((advance.width / K).rounded())
}
let advanceDesign = penDesign

let ascentDesign = CTFontGetAscent(ctFont) / K
let descentDesign = CTFontGetDescent(ctFont) / K
let xHeightDesign = CTFontGetXHeight(ctFont) / K

// MARK: - rasterise

let pad = Int(rasterPpem.rounded(.up)) + 2
var inkMinX: CGFloat = 0, inkMaxX = CGFloat(penDesign) * K
var inkMinY: CGFloat = 0, inkMaxY: CGFloat = 0
for (i, box) in boxes.enumerated() where !box.isEmpty {
    inkMinX = min(inkMinX, positions[i].x + box.minX)
    inkMaxX = max(inkMaxX, positions[i].x + box.maxX)
    inkMinY = min(inkMinY, box.minY)
    inkMaxY = max(inkMaxY, box.maxY)
}
// Keep the raster origin on a design-pixel boundary so block edges line up
// with the font's own grid.
let offX = ((CGFloat(pad) - inkMinX) / K).rounded() * K
let offY = ((CGFloat(pad) - inkMinY) / K).rounded() * K
let width = Int((inkMaxX - inkMinX).rounded(.up)) + pad * 2 + 2
let height = Int((inkMaxY - inkMinY).rounded(.up)) + pad * 2 + 2

guard let ctx = CGContext(
    data: nil, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width,
    space: CGColorSpaceCreateDeviceGray(),
    bitmapInfo: CGImageAlphaInfo.none.rawValue
) else { die("could not create a bitmap context") }

ctx.setShouldAntialias(false)
ctx.setShouldSmoothFonts(false)
ctx.setAllowsFontSubpixelPositioning(false)
ctx.setAllowsFontSubpixelQuantization(false)
ctx.setAllowsFontSmoothing(false)
ctx.interpolationQuality = CGInterpolationQuality.none

ctx.setFillColor(gray: 1, alpha: 1)                            // start from white
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
ctx.setFillColor(gray: 0, alpha: 1)                            // black ink

var drawPositions = positions.map { CGPoint(x: $0.x + offX, y: offY) }
CTFontDrawGlyphs(ctFont, glyphs, &drawPositions, glyphs.count, ctx)

guard let data = ctx.data else { die("bitmap context has no backing store") }
let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)

// MARK: - collapse to the design grid by block majority

// CGBitmapContext backing stores are laid out top-down even though the drawing
// coordinate system is bottom-up, so raster row 0 is the top of the image.
// Each design pixel is a superFactor x superFactor block of raster pixels;
// count the ink in every block, then keep the blocks that are mostly covered.
let blockStride = 1 << 20
var coverage: [Int: Int] = [:]
for row in 0..<height {
    for col in 0..<width where buffer[row * width + col] < 128 {
        coverage[(row / superFactor) * blockStride + (col / superFactor), default: 0] += 1
    }
}

let blockArea = superFactor * superFactor
var blocks = Set<Int>()                                         // row * blockStride + col
var minC = Int.max, maxC = Int.min, minR = Int.max, maxR = Int.min
for (key, count) in coverage where count * 2 > blockArea {
    let row = key / blockStride, col = key % blockStride
    blocks.insert(key)
    minC = min(minC, col); maxC = max(maxC, col)
    minR = min(minR, row); maxR = max(maxR, row)
}
guard !blocks.isEmpty else { die("rendering produced no ink") }

// Trim to the ink box and re-index on a compact grid.
let gridWidth = maxC - minC + 1
let gridHeight = maxR - minR + 1
var trimmed = Set<Int>()
for key in blocks {
    let row = key / blockStride - minR
    let col = key % blockStride - minC
    trimmed.insert(row * gridWidth + col)
}

// Reference rows, in trimmed design-pixel coordinates, for reporting.
func designRow(forRasterY y: CGFloat) -> Int {
    (height - 1 - Int(y.rounded(.down))) / superFactor - minR
}
let baselineRow = designRow(forRasterY: offY)
let xHeightTopRow = designRow(forRasterY: offY + xHeightDesign * K)

if opts.dump {
    var seen = Set<UInt8>()
    for index in 0..<(width * height) { seen.insert(buffer[index]) }
    var histogram: [Int: Int] = [:]
    for count in coverage.values { histogram[count, default: 0] += 1 }
    let top = histogram.sorted { $0.value > $1.value }.prefix(6)
        .map { "\($0.key)x\($0.value)" }.joined(separator: " ")
    var art = ""
    for row in 0..<gridHeight {
        for col in 0..<gridWidth {
            art += trimmed.contains(row * gridWidth + col) ? "##" : ".."
        }
        art += row == baselineRow ? "  <- baseline\n" : "\n"
    }
    FileHandle.standardError.write(Data("""
    raster uses \(seen.count) distinct gray values (1 = no anti-aliasing)
    block coverage histogram (coverage x blocks), blockArea \(blockArea): \(top)
    \(art)
    """.utf8))
}

// MARK: - blow the design grid up onto the icon canvas

let reps = max(1, opts.width / gridWidth)
let markWidth = gridWidth * reps
let markHeight = gridHeight * reps
let originX = (canvas - markWidth) / 2
let originY = (canvas - markHeight) / 2

// Merge horizontal runs so the path stays compact.
var runs: [String] = []
for row in 0..<gridHeight {
    var col = 0
    while col < gridWidth {
        if trimmed.contains(row * gridWidth + col) {
            let start = col
            while col + 1 < gridWidth, trimmed.contains(row * gridWidth + col + 1) { col += 1 }
            let x = originX + start * reps
            let y = originY + row * reps
            let w = (col - start + 1) * reps
            runs.append("M\(x) \(y)h\(w)v\(reps)h-\(w)z")
        }
        col += 1
    }
}

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)"
     viewBox="0 0 \(canvas) \(canvas)">
  <!-- bar-text app icon: black bitmap wordmark on a white rounded card.

       Wordmark "\(opts.text)" set in \(fontName) at a \(opts.ppem)px design size,
       rasterised \(superFactor)x with anti-aliasing, font smoothing and subpixel
       positioning disabled, then collapsed block-by-block to the design grid and
       scaled up \(reps)x as whole square blocks. The glyph grid is
       \(gridWidth)x\(gridHeight) design pixels; the baseline is grid row
       \(baselineRow) and the x-height band spans rows \(xHeightTopRow)...\(baselineRow).

       Regenerate with: swift scripts/build-wordmark.swift

       Font licence: SIL Open Font License 1.1, see packaging/fonts/OFL.txt -->

  <!-- card: \(art)px art square centred in the \(canvas)px canvas, macOS icon
       proportions; hairline edge so the white card reads on white backgrounds -->
  <rect x="\(margin)" y="\(margin)" width="\(art)" height="\(art)" rx="\(corner)" fill="#ffffff"/>
  <rect x="\(margin + 1)" y="\(margin + 1)" width="\(art - 2)" height="\(art - 2)"
        rx="\(corner - 1)" fill="none" stroke="#000000" stroke-opacity="0.07"
        stroke-width="2"/>

  <!-- wordmark -->
  <path fill="#000000" shape-rendering="crispEdges" d="\(runs.joined())"/>
</svg>

"""

do {
    try svg.write(toFile: opts.out, atomically: true, encoding: .utf8)
} catch {
    die("cannot write \(opts.out): \(error.localizedDescription)")
}

print("""
font        \(fontName) (unitsPerEm \(cgFont.unitsPerEm))
text        "\(opts.text)"
design      \(opts.ppem)px, supersampled \(superFactor)x -> \(Int(rasterPpem))px raster
metrics     ascent \(ascentDesign) descent \(descentDesign) x-height \(xHeightDesign) design px; advance total \(advanceDesign)
glyph grid  \(gridWidth)x\(gridHeight) design px, upscale \(reps)x -> \(markWidth)x\(markHeight)px at (\(originX),\(originY))
baseline    grid row \(baselineRow) of \(gridHeight); x-height top row \(xHeightTopRow)
card        \(art)px art; side margins \(originX - margin) / \(margin + art - (originX + markWidth)), top/bottom \(originY - margin) / \(margin + art - (originY + markHeight))
wrote       \(opts.out)
""")
