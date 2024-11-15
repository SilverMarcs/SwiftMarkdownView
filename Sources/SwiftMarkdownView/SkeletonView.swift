//
//  SwiftUIView.swift
//  SwiftMarkdownView
//
//  Created by Zabir Raihan on 09/11/2024.
//

import SwiftUI

internal class SkeletonView: PlatformView {
    private static let cachedBlockRects: [CGRect] = {
        let blockHeight: CGFloat = 16
        let blockSpacing: CGFloat = 8
        let horizontalPadding: CGFloat = 16
        let availableWidth: CGFloat = 1000 // Arbitrary large width
        
        var rects: [CGRect] = []
        var yPosition: CGFloat = blockSpacing
        
        for _ in 0..<50 { // Cache 50 blocks
            let rect = CGRect(x: horizontalPadding, y: yPosition, width: availableWidth - (2 * horizontalPadding), height: blockHeight)
            rects.append(rect)
            yPosition += blockHeight + blockSpacing
        }
        
        return rects
    }()
    
    private var contentHeight: CGFloat = 0
    
    #if os(macOS)
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSkeleton()
    }
    #else
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        drawSkeleton()
    }
    #endif
    
    private func drawSkeleton() {
        #if os(macOS)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        #else
        guard let context = UIGraphicsGetCurrentContext() else { return }
        #endif
        
        let color = PlatformColor.lightGray.withAlphaComponent(0.15).cgColor
        context.setFillColor(color)
        
        for rect in SkeletonView.cachedBlockRects {
            if rect.maxY > contentHeight {
                break
            }
            
            let adjustedRect = CGRect(x: rect.minX, y: rect.minY, width: bounds.width - (2 * rect.minX), height: rect.height)
            
            #if os(macOS)
            let path = CGPath(roundedRect: adjustedRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(path)
            context.fillPath()
            #else
            let path = UIBezierPath(roundedRect: adjustedRect, cornerRadius: 4)
            path.fill()
            #endif
        }
    }
    
    func updateSkeleton(for contentHeight: CGFloat) {
        self.contentHeight = contentHeight
        setNeedsDisplay(bounds)
    }
    
    func fadeOut(completion: @escaping () -> Void) {
        #if os(macOS)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: completion)
        #else
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { _ in
            completion()
        })
        #endif
    }
}
