#if os(macOS)
import AppKit
import QuartzCore

/// Draws a text view into fixed tiles that cover the visible part of it,
/// instead of into the view's own layer.
///
/// AppKit backs a tall view's layer only where it's visible, so each scroll
/// step re-rasterizes the newly exposed strip of every partly visible text
/// view and waits on the render server for the layer's buffer. A tile is
/// drawn once and then only moves while scrolling, and its rasterizing runs
/// off the main thread.
@MainActor
final class MarkdownTextTiles: NSObject, @preconcurrency CALayerDelegate {
    private static let tileHeight: CGFloat = 512

    private unowned let view: MarkdownPlainTextView
    private var tiles: [Int: CALayer] = [:]
    private weak var clipView: NSClipView?

    init(view: MarkdownPlainTextView) {
        self.view = view
    }

    // MARK: - Tracking the viewport

    /// Follows the enclosing clip view as it scrolls, and the view's
    /// ancestors as they move, such as when a row above it changes height.
    func viewDidMoveToWindow() {
        NotificationCenter.default.removeObserver(self)
        clipView = nil
        guard view.window != nil else {
            removeAll()
            return
        }

        var ancestor = view.superview
        while let current = ancestor {
            if let clip = current as? NSClipView {
                // Bounds change on scroll; the frame when the window resizes.
                clip.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(geometryDidChange), name: NSView.boundsDidChangeNotification, object: clip)
                NotificationCenter.default.addObserver(self, selector: #selector(geometryDidChange), name: NSView.frameDidChangeNotification, object: clip)
                clipView = clip
                break
            }
            NotificationCenter.default.addObserver(self, selector: #selector(geometryDidChange), name: NSView.frameDidChangeNotification, object: current)
            ancestor = current.superview
        }
        update()
    }

    @objc private func geometryDidChange(_ notification: Notification) {
        update()
    }

    /// The part of the view the clip view shows, or all of it outside a
    /// scroll view.
    private var viewport: CGRect {
        guard let clipView else { return view.bounds }
        return view.convert(clipView.bounds, from: clipView)
    }

    // MARK: - Tiles

    /// Adds tiles that came into view and removes ones well out of it.
    func update() {
        guard let layer = view.layer, let window = view.window else { return }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            removeAll()
            return
        }

        let height = Self.tileHeight
        let count = Int((bounds.height / height).rounded(.up))
        let viewport = viewport
        // Tiles a little out of view stay, so scrolling back doesn't redraw them.
        let kept = viewport.insetBy(dx: 0, dy: -height).intersection(bounds)

        for (index, tile) in tiles {
            let frame = frame(ofTile: index, in: bounds)
            guard index < count, !kept.isEmpty, frame.intersects(kept) else {
                tile.removeFromSuperlayer()
                tiles[index] = nil
                continue
            }
            if tile.frame != frame {
                tile.frame = frame
                tile.setNeedsDisplay()
            }
        }

        let visible = viewport.intersection(bounds)
        guard !visible.isEmpty else { return }
        let first = max(0, Int(visible.minY / height))
        let last = max(first, min(count - 1, Int((visible.maxY - 1) / height)))
        for index in first...last where tiles[index] == nil {
            let tile = CALayer()
            tile.delegate = self
            tile.anchorPoint = .zero
            tile.isOpaque = false
            tile.drawsAsynchronously = true
            tile.contentsScale = window.backingScaleFactor
            tile.frame = frame(ofTile: index, in: bounds)
            tile.setNeedsDisplay()
            layer.addSublayer(tile)
            tiles[index] = tile
        }
    }

    private func frame(ofTile index: Int, in bounds: CGRect) -> CGRect {
        let top = CGFloat(index) * Self.tileHeight
        return CGRect(x: 0, y: top, width: bounds.width, height: min(Self.tileHeight, bounds.height - top))
    }

    func invalidate(_ rect: CGRect) {
        for tile in tiles.values where tile.frame.intersects(rect) {
            tile.setNeedsDisplay(rect.offsetBy(dx: -tile.frame.minX, dy: -tile.frame.minY))
        }
    }

    func invalidateAll() {
        for tile in tiles.values {
            tile.setNeedsDisplay()
        }
    }

    func scaleDidChange() {
        let scale = view.window?.backingScaleFactor ?? 2
        for tile in tiles.values where tile.contentsScale != scale {
            tile.contentsScale = scale
            tile.setNeedsDisplay()
        }
    }

    private func removeAll() {
        for tile in tiles.values {
            tile.removeFromSuperlayer()
        }
        tiles.removeAll()
    }

    // MARK: - CALayerDelegate

    func draw(_ layer: CALayer, in context: CGContext) {
        let frame = layer.frame
        if !layer.contentsAreFlipped() {
            context.translateBy(x: 0, y: frame.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.translateBy(x: -frame.minX, y: -frame.minY)
        let dirtyRect = context.boundingBoxOfClipPath.intersection(frame)
        guard !dirtyRect.isEmpty else { return }
        view.drawTile(dirtyRect, in: context)
    }

    func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        NSNull()
    }
}
#endif
