// Dessine le fond de la fenêtre du DMG : nuit sombre, halo aurore repris de l'icône, flèche
// lumineuse entre l'app et Applications. Les positions suivent scripts/dmg-layout.py.
//   swift scripts/dmg-background.swift <fond.png> <fond@2x.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage : dmg-background.swift <fond.png> <fond@2x.png>\n", stderr)
    exit(2)
}

let width = 660.0
let height = 420.0

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(scale: CGFloat, to path: String) {
    let context = CGContext(
        data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // repère en points, origine en haut à gauche comme dans la maquette
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    let night = CGGradient(colorsSpace: space, colors: [color(0x12141f), color(0x05060c)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(night, start: .zero, end: CGPoint(x: 0, y: height), options: [])

    // halos : un dégradé radial étiré par ellipse, plus doux qu'un flou et sans Core Image
    for (center, radii, hex) in [
        (CGPoint(x: 130, y: 380), CGSize(width: 330, height: 190), 0xff5fa2),
        (CGPoint(x: 380, y: 420), CGSize(width: 330, height: 190), 0x7b5cff),
        (CGPoint(x: 620, y: 370), CGSize(width: 310, height: 180), 0x1fd1ff),
    ] as [(CGPoint, CGSize, UInt32)] {
        let glow = CGGradient(colorsSpace: space,
                              colors: [color(hex, 0.8), color(hex, 0.4), color(hex, 0)] as CFArray,
                              locations: [0, 0.45, 1])!
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: radii.width, y: radii.height)
        context.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        context.restoreGState()
    }

    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 262, y: 190))
    arrow.addLine(to: CGPoint(x: 378, y: 190))
    arrow.move(to: CGPoint(x: 352, y: 164))
    arrow.addLine(to: CGPoint(x: 380, y: 190))
    arrow.addLine(to: CGPoint(x: 352, y: 216))
    context.setStrokeColor(color(0xffffff))
    context.setLineWidth(7)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    // premier passage avec une ombre blanche = halo, second passage net par-dessus
    context.saveGState()
    context.setShadow(offset: .zero, blur: 16, color: color(0xffffff, 0.8))
    context.addPath(arrow)
    context.strokePath()
    context.restoreGState()
    context.addPath(arrow)
    context.strokePath()

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        fputs("écriture impossible : \(path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
}

render(scale: 1, to: args[1])
render(scale: 2, to: args[2])
