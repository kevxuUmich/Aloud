import CoreGraphics
import CoreText
import Foundation

/// Builds a real PDF from lines of text, one array per page, top to bottom,
/// so PDFKit's `string` comes back in reading order.
enum TestPDF {
    static func make(pages: [[String]]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 600)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        for lines in pages {
            ctx.beginPDFPage(nil)
            var y: CGFloat = 560
            for line in lines {
                let attr = NSAttributedString(string: line, attributes: [fontKey: font])
                let ctLine = CTLineCreateWithAttributedString(attr)
                ctx.textPosition = CGPoint(x: 40, y: y)
                CTLineDraw(ctLine, ctx)
                y -= 18
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}
