//
//  StatCardCustomizationOverlay.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/27/25.
//


//
//  StatCardCustomizationOverlay.swift
//  DynastyStatDrop
//
//  Restored component required by DSDDashboard
//

import SwiftUI

struct StatCardCustomizationOverlay: View {
    let title: String
    let allItems: [Category]
    @Binding var selectedItems: Set<Category>
    let maxSelections: Int
    let valueProvider: (Category) -> String
    let onClose: () -> Void
    let glowColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            helperText
            itemsList
            doneButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(glowColor.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Sections
    
    private var header: some View {
        HStack {
            Text(title)
                .font(.custom("Phatt", size: 24))
                .foregroundColor(glowColor)
                .underline()
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.85))
                    .font(.title2)
            }
            .accessibilityLabel("Close customization overlay")
        }
    }
    
    private var helperText: some View {
        Text("Select up to \(maxSelections) stats to display on this card.")
            .font(.caption)
            .foregroundColor(.white.opacity(0.6))
    }
    
    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(allItems, id: \.self) { cat in
                    let isSelected = selectedItems.contains(cat)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cat.abbreviation)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text(valueProvider(cat))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.yellow)
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundColor(isSelected ? glowColor : .white.opacity(0.4))
                            .font(.title3)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? glowColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(cat) }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var doneButton: some View {
        Button(action: onClose) {
            Text("Done")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(glowColor))
        }
        .padding(.top, 4)
    }
    
    // MARK: - Logic
    
    private func toggle(_ cat: Category) {
        if selectedItems.contains(cat) {
            selectedItems.remove(cat)
        } else if selectedItems.count < maxSelections {
            selectedItems.insert(cat)
        }
    }
}