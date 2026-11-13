// Découpe l'artwork plein cadre au gabarit d'icône macOS : carré arrondi de 824 px centré
// sur un canevas 1024 transparent, rayon 184, avec l'ombre portée du gabarit Apple.
//   swift scripts/mask-icon.swift <artwork.png> <master.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage : mask-icon.swift <artwork.png> <master.png>\n", stderr)
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("image illisible : \(args[1])\n", stderr)
    exit(1)
}

let size = 1024
let inset = 100
let radius: CGFloat = 184
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let square = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil)

// l'ombre se dessine sous une forme pleine ; y négatif = vers le bas en coordonnées CoreGraphics
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.3))
context.addPath(shape)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.fillPath()
context.restoreGState()

context.addPath(shape)
context.clip()
context.draw(artwork, in: square)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    fputs("écriture impossible : \(args[2])\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
