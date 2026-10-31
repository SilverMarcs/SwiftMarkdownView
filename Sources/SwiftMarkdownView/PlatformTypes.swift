import Foundation

#if os(macOS)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformView = NSView
public typealias PlatformFontDescriptor = NSFontDescriptor
public typealias PlatformBezierPath = NSBezierPath
public typealias PlatformImage = NSImage

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

extension PlatformFont {
    nonisolated var markdownItalic: PlatformFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.italic))
        return PlatformFont(descriptor: descriptor, size: pointSize) ?? self
    }
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

public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformView = UIView
public typealias PlatformFontDescriptor = UIFontDescriptor
public typealias PlatformBezierPath = UIBezierPath
public typealias PlatformImage = UIImage

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

extension PlatformFont {
    nonisolated var markdownItalic: PlatformFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitItalic)) else { return self }
        return PlatformFont(descriptor: descriptor, size: pointSize)
    }
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
