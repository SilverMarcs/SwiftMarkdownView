import Foundation

#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformView = NSView
typealias PlatformFontDescriptor = NSFontDescriptor
typealias PlatformBezierPath = NSBezierPath

extension PlatformColor {
    nonisolated static var markdownLabel: PlatformColor { .labelColor }
    nonisolated static var markdownSecondaryLabel: PlatformColor { .secondaryLabelColor }
    nonisolated static var markdownTertiaryLabel: PlatformColor { .tertiaryLabelColor }
    nonisolated static var markdownSeparator: PlatformColor { .separatorColor }
    nonisolated static var markdownAccent: PlatformColor { .controlAccentColor }
}

extension PlatformFontDescriptor.SymbolicTraits {
    static var markdownBold: PlatformFontDescriptor.SymbolicTraits { .bold }
    static var markdownMonoSpace: PlatformFontDescriptor.SymbolicTraits { .monoSpace }
}

extension PlatformBezierPath {
    convenience init(roundedRect: CGRect, cornerRadius: CGFloat) {
        self.init(roundedRect: roundedRect, xRadius: cornerRadius, yRadius: cornerRadius)
    }

    func addLineTo(_ point: CGPoint) {
        line(to: point)
    }
}

#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformView = UIView
typealias PlatformFontDescriptor = UIFontDescriptor
typealias PlatformBezierPath = UIBezierPath

extension PlatformColor {
    nonisolated static var markdownLabel: PlatformColor { .label }
    nonisolated static var markdownSecondaryLabel: PlatformColor { .secondaryLabel }
    nonisolated static var markdownTertiaryLabel: PlatformColor { .tertiaryLabel }
    nonisolated static var markdownSeparator: PlatformColor { .separator }
    nonisolated static var markdownAccent: PlatformColor { .tintColor }
}

extension PlatformFontDescriptor.SymbolicTraits {
    static var markdownBold: PlatformFontDescriptor.SymbolicTraits { .traitBold }
    static var markdownMonoSpace: PlatformFontDescriptor.SymbolicTraits { .traitMonoSpace }
}

extension PlatformBezierPath {
    func addLineTo(_ point: CGPoint) {
        addLine(to: point)
    }
}

#endif

extension NSAttributedString {
    nonisolated var fullRange: NSRange { NSRange(location: 0, length: length) }
}
