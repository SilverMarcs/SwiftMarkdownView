//
//  SwiftUIView.swift
//  SwiftMarkdownView
//
//  Created by Zabir Raihan on 09/11/2024.
//

import SwiftUI

internal class SkeletonView: PlatformView {
    private var blockRects: [CGRect] = []
    
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
        
        for rect in blockRects {
            #if os(macOS)
            let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(path)
            context.fillPath()
            #else
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            path.fill()
            #endif
        }
    }
    
    func updateSkeleton(for contentHeight: CGFloat) {
        let blockHeight: CGFloat = 16
        let blockSpacing: CGFloat = 8
        let horizontalPadding: CGFloat = 16
        let availableWidth = bounds.width - (2 * horizontalPadding)
        
        var yPosition: CGFloat = blockSpacing
        var newBlockRects: [CGRect] = []
        
        while yPosition < contentHeight - blockHeight {
            let rect = CGRect(x: horizontalPadding, y: yPosition, width: availableWidth, height: blockHeight)
            newBlockRects.append(rect)
            yPosition += blockHeight + blockSpacing
        }
        
        blockRects = newBlockRects
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
