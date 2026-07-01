//
//  Theme.swift
//  ITBizEnglish
//
//  Centralized design tokens — a Duolingo-inspired palette, spacing, corner
//  radii and a clean background — so the whole app stays visually consistent
//  and playful. Pair with DuoKit.swift for the 3D buttons, choice cards and
//  chunky progress bar.
//

import SwiftUI
import UIKit

enum Theme {
    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    // MARK: Corners
    enum Radius {
        static let card: CGFloat = 20
        static let pill: CGFloat = 14
        static let button: CGFloat = 16
        static let choice: CGFloat = 12   // answer cards — tighter than buttons
    }

    // MARK: Accent per tone
    static func accent(for tone: Tone) -> Color {
        switch tone {
        case .casual:       return .duoBlue
        case .professional: return .duoIndigo
        }
    }
}

// MARK: - Duolingo-inspired palette
//
// Each "action" color comes with a darker `edge` used for the 3D button lip.

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Adaptive color that swaps between light & dark appearances.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }

    // Brand "action" colors stay the same in both appearances.

    // Primary brand green ("feather green")
    static let duoGreen      = Color(hex: 0x58CC02)
    static let duoGreenEdge  = Color(hex: 0x4CAF00)

    // Blue ("macaw")
    static let duoBlue       = Color(hex: 0x1CB0F6)
    static let duoBlueEdge   = Color(hex: 0x1899D6)

    // Indigo / purple (professional tone, accents)
    static let duoIndigo     = Color(hex: 0xA560E8)
    static let duoIndigoEdge = Color(hex: 0x8A4FC4)

    // Red ("cardinal") — wrong answers
    static let duoRed        = Color(hex: 0xFF4B4B)
    static let duoRedEdge    = Color(hex: 0xE63A3A)

    // Gold ("bee") — XP / highlights
    static let duoGold       = Color(hex: 0xFFC800)
    static let duoGoldEdge   = Color(hex: 0xE6A700)

    // Neutrals — adaptive so text/borders/fills read well in dark mode too.
    static let duoInk        = dyn(0x4B4B4B, 0xF2F2F2)   // primary text ("eel")
    static let duoWolf       = dyn(0x777777, 0xA2A2A6)   // secondary text
    static let duoSwan       = dyn(0xE5E5E5, 0x3A3A3C)   // borders / inactive
    static let duoPolar      = dyn(0xF7F7F7, 0x1C1C1E)   // light fill
    static let duoHare       = dyn(0xAFAFAF, 0x6C6C70)   // disabled text / lip

    /// Soft tinted fill used in the answer feedback panel.
    static let duoCorrectFill = dyn(0xD7FFB8, 0x18331C)
    static let duoCorrectText = dyn(0x58A700, 0x8BE04A)
    static let duoWrongFill    = dyn(0xFFDFE0, 0x3A1A1C)
    static let duoWrongText    = dyn(0xEA2B2B, 0xFF7B7B)

    /// Answer-card tints — pastel fill + softer border like Duolingo's choice
    /// cards (the saturated palette colors are too harsh for a selected card).
    static let duoSelFill     = dyn(0xDDF4FF, 0x10303F)   // selected (blue)
    static let duoSelBorder   = dyn(0x84D8FF, 0x2A6E92)
    static let duoSelText     = dyn(0x1899D6, 0x6FC3F0)
    static let duoWrongBorder = dyn(0xFF9595, 0xB5484A)   // wrong (red) border

    /// Correct answer-card greens (exact Duolingo values).
    static let duoOkBorder = dyn(0xA5EA6F, 0x67B23C)
    static let duoOkFill   = dyn(0xD4FBB5, 0x1F3D12)
    static let duoOkText   = dyn(0x5EA125, 0x9BE25A)

    /// App-wide accent from the user's chosen theme (Settings).
    static var brand: Color     { AppSettings.shared.theme.primary }
    static var brandEdge: Color { AppSettings.shared.theme.edge }
}

/// Lets the palette be used with leading-dot syntax in `foregroundStyle`,
/// `fill`, `tint`, etc. (e.g. `.foregroundStyle(.duoInk)`). These just mirror
/// the `Color` constants above so dark-mode adaptivity is defined in one place.
extension ShapeStyle where Self == Color {
    static var duoGreen: Color      { .duoGreen }
    static var duoGreenEdge: Color  { .duoGreenEdge }
    static var duoBlue: Color       { .duoBlue }
    static var duoBlueEdge: Color   { .duoBlueEdge }
    static var duoIndigo: Color     { .duoIndigo }
    static var duoIndigoEdge: Color { .duoIndigoEdge }
    static var duoRed: Color        { .duoRed }
    static var duoRedEdge: Color    { .duoRedEdge }
    static var duoGold: Color       { .duoGold }
    static var duoGoldEdge: Color   { .duoGoldEdge }
    static var duoInk: Color        { .duoInk }
    static var duoWolf: Color       { .duoWolf }
    static var duoSwan: Color       { .duoSwan }
    static var duoPolar: Color      { .duoPolar }
    static var duoHare: Color       { .duoHare }
    static var duoCorrectFill: Color { .duoCorrectFill }
    static var duoCorrectText: Color { .duoCorrectText }
    static var duoWrongFill: Color   { .duoWrongFill }
    static var duoWrongText: Color   { .duoWrongText }
    static var duoSelFill: Color     { .duoSelFill }
    static var duoSelBorder: Color   { .duoSelBorder }
    static var duoSelText: Color     { .duoSelText }
    static var duoWrongBorder: Color { .duoWrongBorder }
    static var duoOkBorder: Color    { .duoOkBorder }
    static var duoOkFill: Color      { .duoOkFill }
    static var duoOkText: Color      { .duoOkText }
    static var brand: Color          { .brand }
    static var brandEdge: Color      { .brandEdge }
}

// MARK: - Reusable clean background

struct AppBackground: View {
    var body: some View {
        Color(.systemBackground).ignoresSafeArea()
    }
}
