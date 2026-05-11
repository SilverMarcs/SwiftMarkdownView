import Foundation

#if os(macOS)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformView = NSView
public typealias PlatformFontDescriptor = NSFontDescriptor
public typealias PlatformBezierPath = NSBezierPath

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

public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformView = UIView
public typealias PlatformFontDescriptor = UIFontDescriptor
public typealias PlatformBezierPath = UIBezierPath

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
