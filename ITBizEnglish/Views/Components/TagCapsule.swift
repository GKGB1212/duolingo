//
//  TagCapsule.swift
//  ITBizEnglish
//
//  A single rounded "pill" used to display generated tags.
//

import SwiftUI

struct TagCapsule: View {
    let text: String
    var color: Color = .blue

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
    }
}

/// A wrapping row of tag capsules (flows to the next line when out of space).
struct TagFlow: View {
    let tags: [String]
    var color: Color = .blue

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagCapsule(text: tag, color: color)
            }
        }
    }
}

#Preview {
    TagFlow(tags: ["Scrum", "Deadline", "Commitment", "Business English"])
        .padding()
}
