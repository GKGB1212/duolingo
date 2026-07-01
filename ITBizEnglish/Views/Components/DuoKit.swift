//
//  DuoKit.swift
//  ITBizEnglish
//
//  Duolingo-style building blocks shared across the app:
//   • DuoButtonStyle      — chunky 3D button with a darker bottom "lip" that
//                           compresses when pressed.
//   • DuoProgressBar      — fat rounded progress track with a glossy highlight.
//   • DuoChoiceCard       — a selectable answer card (normal/selected/correct/
//                           wrong) with the signature 2px border + bottom edge.
//
//  All text uses SF Rounded (applied app-wide via `.fontDesign(.rounded)`).
//

import SwiftUI

// MARK: - 3D button

struct DuoButtonStyle: ButtonStyle {
    var color: Color = .duoGreen
    var edge: Color = .duoGreenEdge
    var foreground: Color = .white
    var depth: CGFloat = 4
    /// When false the button renders flat & gray (used for disabled CTAs).
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
        let pressed = configuration.isPressed && enabled
        let face = enabled ? color : Color.duoSwan
        let lip  = enabled ? edge  : Color.duoSwan
        let fg   = enabled ? foreground : Color.duoHare

        return configuration.label
            .font(.headline.weight(.heavy))
            .textCase(.uppercase)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: 20)
            .padding(.vertical, 14)
            .background(shape.fill(face))
            .offset(y: pressed ? depth : 0)
            .background(shape.fill(lip).offset(y: depth))   // static lip below the face
            .padding(.bottom, depth)
            .animation(.easeOut(duration: 0.06), value: pressed)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && enabled { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == DuoButtonStyle {
    static var duoGreen: DuoButtonStyle { .init(color: .duoGreen, edge: .duoGreenEdge) }
    static var duoBlue:  DuoButtonStyle { .init(color: .duoBlue,  edge: .duoBlueEdge) }
    static var duoRed:   DuoButtonStyle { .init(color: .duoRed,   edge: .duoRedEdge) }
    static func duo(_ color: Color, edge: Color, enabled: Bool = true) -> DuoButtonStyle {
        .init(color: color, edge: edge, enabled: enabled)
    }
    /// The app's themed accent button.
    static var brand: DuoButtonStyle { .init(color: .brand, edge: .brandEdge) }
    /// A themed primary button that turns flat-gray when `enabled` is false.
    static func duoPrimary(enabled: Bool) -> DuoButtonStyle {
        .init(color: .brand, edge: .brandEdge, enabled: enabled)
    }
}

// MARK: - Progress bar

struct DuoProgressBar: View {
    var value: Double          // 0...1
    var tint: Color = .brand
    var height: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, value)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.duoSwan)
                if w > 0 {
                    Capsule()
                        .fill(tint)
                        .overlay(alignment: .top) {
                            // glossy highlight strip
                            Capsule()
                                .fill(Color.white.opacity(0.35))
                                .frame(height: height * 0.28)
                                .padding(.horizontal, 6)
                                .padding(.top, 3)
                        }
                        .frame(width: max(w, height))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Selectable answer card

enum DuoChoiceState { case normal, selected, correct, wrong, dimmed }

struct DuoChoiceCard<Content: View>: View {
    var state: DuoChoiceState
    var cornerRadius: CGFloat = Theme.Radius.choice
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    private var border: Color {
        switch state {
        case .normal, .dimmed: return .duoSwan
        case .selected:        return .duoSelBorder
        case .correct:         return .duoOkBorder
        case .wrong:           return .duoWrongBorder
        }
    }
    private var fill: Color {
        switch state {
        case .normal, .dimmed: return Color(.systemBackground)
        case .selected:        return .duoSelFill
        case .correct:         return .duoOkFill
        case .wrong:           return .duoWrongFill
        }
    }
    private var textTint: Color {
        switch state {
        case .selected: return .duoSelText
        case .correct:  return .duoOkText
        case .wrong:    return .duoWrongText
        default:        return .duoInk
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return Button(action: action) {
            content()
                .font(.body.weight(.bold))
                .foregroundStyle(textTint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)            // text centered, Duolingo-style
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 16)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(border, lineWidth: 2))
                // Bottom "shelf": an identical card in the border color peeking
                // out a few px below the face. It follows the corner radius
                // cleanly, so the thicker bottom edge has no notch at the corners.
                .background(shape.fill(border).offset(y: 3))
                .padding(.bottom, 3)
                .opacity(state == .dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: state)
        .correctCelebration(trigger: state == .correct, cornerRadius: cornerRadius)
    }
}

// MARK: - "Correct!" celebration (shared everywhere)

/// The signature Duolingo "correct" pop, reused across every module so the
/// feedback feels identical: the button squashes (wider + shorter), springs up
/// with an overshoot, a glossy shine sweeps left → right, a 4-point sparkle
/// glints on the left half as the shine crosses it, and a soft drop shadow
/// stays beneath the button while it's lifted.
struct CorrectCelebration: ViewModifier {
    /// Flip false → true to fire the celebration once.
    var trigger: Bool
    var cornerRadius: CGFloat = Theme.Radius.button
    /// The grey "socket" left behind at the resting position (Duolingo-style).
    var shadowColor: Color = .duoSwan

    @State private var sx: CGFloat = 1       // horizontal scale
    @State private var sy: CGFloat = 1       // vertical scale
    @State private var lift: CGFloat = 0     // how far it jumps up
    @State private var shadow: CGFloat = 0   // shadow visibility (0...1)
    @State private var sweep = false         // glossy bar swept across
    @State private var sparkle = false       // 4-point star flash

    func body(content: Content) -> some View {
        content
            // Opaque base so nothing shows through the button face.
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            // Soft glossy sheen that sweeps diagonally across the face.
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.6), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.65)
                        .rotationEffect(.degrees(22))
                        .offset(x: sweep ? w * 1.2 : -w * 1.2)
                        .opacity(sweep ? 1 : 0)
                }
                .allowsHitTesting(false)
                .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            // Two soft white sparkles that glint *inside* the button (not a loud
            // yellow star): one top-left, one bottom-right, as the sheen passes.
            .overlay(alignment: .topLeading) { sparkleGlint(size: 16) .padding(.leading, 18).padding(.top, 10) }
            .overlay(alignment: .bottomTrailing) { sparkleGlint(size: 12) .padding(.trailing, 20).padding(.bottom, 12) }
            .scaleEffect(x: sx, y: sy, anchor: .center)
            .offset(y: -lift)
            // Grey socket pinned to the resting frame (placed AFTER scale/offset
            // so it never scales or moves) — the button pops up out of it.
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(shadowColor)
                    .opacity(shadow)
            )
            .onChange(of: trigger) { _, on in if on { run() } }
    }

    /// A small white 4-point glint that reads as light catching the button face,
    /// rather than a separate yellow star sitting on top of it.
    private func sparkleGlint(size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(.white)
            .shadow(color: .white.opacity(0.9), radius: 3)
            .scaleEffect(sparkle ? 1 : 0.1)
            .rotationEffect(.degrees(sparkle ? 0 : -90))
            .opacity(sparkle ? 0.95 : 0)
            .allowsHitTesting(false)
    }

    private func run() {
        sweep = false; sparkle = false
        // 1) A slightly slower, softer anticipation dip — Duolingo eases in here.
        withAnimation(.easeInOut(duration: 0.08)) { sx = 1.04; sy = 0.94 }
        // 2) Then a snappier pop straight up off the grey socket.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.17, dampingFraction: 0.52)) {
                sx = 1; sy = 1; lift = 13; shadow = 1
            }
            // Sheen sweeps across quickly while it hangs up high.
            withAnimation(.easeInOut(duration: 0.34)) { sweep = true }
            // Sparkles glint as the sheen crosses (~mid-sweep).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { sparkle = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.easeOut(duration: 0.2)) { sparkle = false }
                }
            }
            // 3) Drop back down onto the socket sooner — shorter total bounce.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                    lift = 0; shadow = 0
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sweep = false }
    }
}

extension View {
    /// Applies the shared "correct answer" celebration. Fires once each time
    /// `trigger` transitions to `true`.
    func correctCelebration(trigger: Bool,
                            cornerRadius: CGFloat = Theme.Radius.button,
                            shadowColor: Color = .duoSwan) -> some View {
        modifier(CorrectCelebration(trigger: trigger, cornerRadius: cornerRadius, shadowColor: shadowColor))
    }
}

// MARK: - Icon + color picker (deck / set appearance)

/// Lets the user pick an SF Symbol avatar and an accent color for a deck or set.
struct IconColorPicker: View {
    let onSave: (String, UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var icon: String
    @State private var colorHex: UInt32

    /// Accent colors offered.
    static let palette: [UInt32] = [
        0x58CC02, 0x1CB0F6, 0xA560E8, 0xFF6FB5,
        0x3D5A98, 0xB07D56, 0xFF9600, 0xFF4B4B
    ]

    init(icon: String, colorHex: UInt32, onSave: @escaping (String, UInt32) -> Void) {
        self.onSave = onSave
        _icon = State(initialValue: icon)
        _colorHex = State(initialValue: colorHex)
    }

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Live preview tile.
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(hex: colorHex)).frame(width: 84, height: 84)
                        Image(systemName: icon).font(.system(size: 38)).foregroundStyle(.white)
                    }
                    .padding(.top, Theme.Spacing.sm)

                    // Colors.
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(Self.palette, id: \.self) { hex in
                            Circle().fill(Color(hex: hex))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(Color.duoInk.opacity(colorHex == hex ? 0.9 : 0), lineWidth: 3))
                                .onTapGesture { colorHex = hex }
                        }
                    }

                    // Icons.
                    LazyVGrid(columns: iconColumns, spacing: Theme.Spacing.md) {
                        ForEach(DeckIcon.choices, id: \.self) { sym in
                            let isOn = sym == icon
                            Button { icon = sym } label: {
                                Image(systemName: sym)
                                    .font(.title2)
                                    .foregroundStyle(isOn ? .white : .duoInk)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isOn ? AnyShapeStyle(Color(hex: colorHex)) : AnyShapeStyle(Color.duoPolar)))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(isOn ? Color(hex: colorHex) : Color.duoSwan, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle("Icon & màu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { onSave(icon, colorHex); dismiss() }
                }
            }
        }
    }
}

// MARK: - Duolingo-style alert popup

/// Data for a custom, Duolingo-styled modal popup (replaces the plain system
/// `.alert`): a colored icon, title, message, a chunky 3D confirm button and an
/// optional plain cancel action.
struct DuoAlertData: Identifiable {
    let id = UUID()
    var icon: String = "exclamationmark.triangle.fill"
    var iconColor: Color = .duoRed
    var title: String
    var message: String
    var confirmTitle: String = "OK"
    var confirmColor: Color = .brand
    var confirmEdge: Color = .brandEdge
    var onConfirm: (() -> Void)? = nil
    var cancelTitle: String? = nil
    var onCancel: (() -> Void)? = nil
}

private struct DuoAlertOverlay: View {
    let data: DuoAlertData
    let dismiss: () -> Void
    @State private var appear = false

    var body: some View {
        ZStack {
            Color.black.opacity(appear ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { if data.cancelTitle != nil { cancel() } }

            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(data.iconColor.opacity(0.16)).frame(width: 74, height: 74)
                    Image(systemName: data.icon)
                        .font(.system(size: 34, weight: .bold)).foregroundStyle(data.iconColor)
                }
                Text(data.title)
                    .font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
                    .multilineTextAlignment(.center)
                if !data.message.isEmpty {
                    Text(data.message)
                        .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: Theme.Spacing.sm) {
                    Button(data.confirmTitle) { confirm() }
                        .buttonStyle(.duo(data.confirmColor, edge: data.confirmEdge))
                    if let cancelTitle = data.cancelTitle {
                        Button(cancelTitle) { cancel() }
                            .buttonStyle(.plain)
                            .font(.headline.weight(.heavy)).foregroundStyle(.duoWolf)
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.duoSwan, lineWidth: 2))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(Theme.Spacing.lg)
            .scaleEffect(appear ? 1 : 0.85)
            .opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { appear = true } }
    }

    private func confirm() { let a = data.onConfirm; close { a?() } }
    private func cancel() { let a = data.onCancel; close { a?() } }
    private func close(_ then: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.14)) { appear = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dismiss(); then() }
    }
}

extension View {
    /// Presents a custom Duolingo-styled popup while `item` is non-nil.
    func duoAlert(_ item: Binding<DuoAlertData?>) -> some View {
        overlay {
            if let data = item.wrappedValue {
                DuoAlertOverlay(data: data) { item.wrappedValue = nil }
            }
        }
    }
}

// MARK: - Card surface

extension View {
    /// A clean Duolingo card: white fill, 2px swan border, soft thick bottom edge.
    func duoCard(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.duoSwan, lineWidth: 2))
    }
}
