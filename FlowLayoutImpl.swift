//
//  FlowLayoutImpl.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/25/25.
//


//
//  FlowLayoutCompat.swift
//  DynastyStatDrop
//
//  Extracted reusable flow / wrap layout used for pill displays (strengths / weaknesses, etc.).
//  Originally embedded in DSDDashboard; separated so other view files (e.g. TeamStatExpandedView)
//  can compile without depending on that monolithic file.
//

import SwiftUI

// MARK: - iOS 16+ Custom Layout Implementation
@available(iOS 16.0, *)
fileprivate struct FlowLayoutImpl: Layout {
    let spacing: CGFloat
    let runSpacing: CGFloat
    
    init(spacing: CGFloat = 8, runSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.runSpacing = runSpacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + runSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        return CGSize(
            width: proposal.width ?? min(maxWidth, currentX),
            height: currentY + lineHeight
        )
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + runSpacing
                lineHeight = 0
            }
            sub.place(
                at: CGPoint(x: bounds.minX + currentX, y: bounds.minY + currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

// MARK: - Public FlowLayout (iOS 16+) & Fallback (iOS 15)

@available(iOS 16.0, *)
fileprivate struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let runSpacing: CGFloat
    let content: (Item) -> Content
    
    init(items: [Item],
         spacing: CGFloat = 8,
         runSpacing: CGFloat = 8,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.spacing = spacing
        self.runSpacing = runSpacing
        self.content = content
    }
    
    var body: some View {
        FlowLayoutImpl(spacing: spacing, runSpacing: runSpacing) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

// Simple vertical fallback for iOS < 16
fileprivate struct FlowLayoutFallback<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

// MARK: - Compatibility Wrapper

struct FlowLayoutCompat<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let runSpacing: CGFloat
    let content: (Item) -> Content
    
    init(items: [Item],
         spacing: CGFloat = 8,
         runSpacing: CGFloat = 8,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.spacing = spacing
        self.runSpacing = runSpacing
        self.content = content
    }
    
    var body: some View {
        if #available(iOS 16.0, *) {
            FlowLayout(items: items, spacing: spacing, runSpacing: runSpacing, content: content)
        } else {
            FlowLayoutFallback(items: items, content: content)
        }
    }
}