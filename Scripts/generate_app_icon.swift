// Original vector artwork for VisionStream. No stock art or SF Symbol assets.
import AppKit
import Foundation

let base=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let assets=base.appendingPathComponent("VisionStream/Assets.xcassets")
let icon=assets.appendingPathComponent("AppIcon.solidimagestack")
func json(_ object:Any,_ file:URL) throws {
    try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]).write(to:file)
}
let info:[String:Any]=["author":"xcode","version":1]
try json(["info":info],assets.appendingPathComponent("Contents.json"))
try json(["info":info,"layers":[["filename":"Front.solidimagestacklayer"],["filename":"Middle.solidimagestacklayer"],["filename":"Back.solidimagestacklayer"]]],icon.appendingPathComponent("Contents.json"))
func render(_ name:String,_ paint:(CGContext)->Void) throws -> CGImage {
    let color=CGColorSpace(name:CGColorSpace.sRGB)!
    let context=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:0,space:color,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true);context.setShouldAntialias(true)
    paint(context)
    let image=context.makeImage()!
    let layer=icon.appendingPathComponent(name+".solidimagestacklayer")
    try json(["info":info],layer.appendingPathComponent("Contents.json"))
    try json(["info":info,"images":[["idiom":"vision","scale":"2x","filename":"Layer.png"]]],layer.appendingPathComponent("Content.imageset/Contents.json"))
    try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:layer.appendingPathComponent("Content.imageset/Layer.png"))
    return image
}
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->CGColor { CGColor(srgbRed:r,green:g,blue:b,alpha:a) }
let back=try render("Back") { c in
    let gradient=CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:[color(0.025,0.07,0.15),color(0.03,0.24,0.34),color(0.04,0.43,0.48)] as CFArray,locations:[0,0.6,1])!
    c.drawLinearGradient(gradient,start:CGPoint(x:180,y:100),end:CGPoint(x:860,y:960),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
    c.setStrokeColor(color(0.3,0.83,0.85,0.1));c.setLineWidth(5)
    c.strokeEllipse(in:CGRect(x:130,y:130,width:764,height:764))
}
let middle=try render("Middle") { c in
    let frame=CGPath(roundedRect:CGRect(x:194,y:306,width:636,height:412),cornerWidth:156,cornerHeight:156,transform:nil)
    c.setShadow(offset:CGSize(width:0,height:-18),blur:38,color:color(0,0.01,0.05,0.55))
    c.addPath(frame);c.setFillColor(color(0.06,0.17,0.25,0.86));c.fillPath();c.setShadow(offset:.zero,blur:0,color:nil)
    c.addPath(frame);c.setLineWidth(19);c.setStrokeColor(color(0.36,0.93,0.94));c.strokePath()
    c.setStrokeColor(color(0.75,1,1,0.32));c.setLineWidth(4)
    c.addPath(CGPath(roundedRect:CGRect(x:220,y:332,width:584,height:360),cornerWidth:130,cornerHeight:130,transform:nil));c.strokePath()
}
let front=try render("Front") { c in
    let path=CGMutablePath();path.move(to:CGPoint(x:457,y:407));path.addLine(to:CGPoint(x:457,y:617));path.addLine(to:CGPoint(x:635,y:512));path.closeSubpath()
    c.setShadow(offset:CGSize(width:0,height:-7),blur:18,color:color(0,0.04,0.10,0.6))
    c.addPath(path);c.setFillColor(color(0.94,1,1));c.fillPath()
}
let preview=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
for image in [back,middle,front] { preview.draw(image,in:CGRect(x:0,y:0,width:1024,height:1024)) }
let output=base.appendingPathComponent("Submission/Artwork")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
try NSBitmapImageRep(cgImage:preview.makeImage()!).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("Icon-preview.png"))
print("Generated original three-layer visionOS AppIcon")
