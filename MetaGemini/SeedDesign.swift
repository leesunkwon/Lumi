//
//  SeedDesign.swift
//  MetaGemini
//
//  SEED의 역할 기반 토큰을 SwiftUI와 Lumi 브랜드에 맞게 매핑합니다.
//

import SwiftUI
import UIKit

enum SeedColor {
    // Foreground
    static let fgNeutral = adaptive(light: 0x1A1C20, dark: 0xF3F4F5)
    static let fgMuted = adaptive(light: 0x555D6D, dark: 0xDCDEE3)
    static let fgSubtle = adaptive(light: 0x868B94, dark: 0xB0B3BA)
    static let fgDisabled = adaptive(light: 0xD1D3D8, dark: 0x5B606A)
    static let fgInverted = adaptive(light: 0xFFFFFF, dark: 0xF7F8F9)

    // Lumi brand role. SEED의 brand 역할에 Lumi의 보라색 팔레트를 적용합니다.
    static let brand = adaptive(light: 0x6D50CB, dark: 0xA78DF0)
    static let brandPressed = adaptive(light: 0x50379B, dark: 0x8969EA)
    static let brandWeak = adaptive(light: 0xEFEAFE, dark: 0x28213B)
    static let brandWeakPressed = adaptive(light: 0xE1D8FF, dark: 0x3B2873)

    // Semantic roles
    static let positive = adaptive(light: 0x079171, dark: 0x22B27F)
    static let positiveWeak = adaptive(light: 0xEDFAF6, dark: 0x202926)
    static let informative = adaptive(light: 0x217CF9, dark: 0x41A2F9)
    static let informativeWeak = adaptive(light: 0xEFF6FF, dark: 0x202742)
    static let warning = adaptive(light: 0x9B7821, dark: 0xCA901C)
    static let warningWeak = adaptive(light: 0xFFF7DE, dark: 0x302819)
    static let critical = adaptive(light: 0xFA342C, dark: 0xFF6E60)
    static let criticalPressed = adaptive(light: 0xCA1D13, dark: 0xFA342C)
    static let criticalWeak = adaptive(light: 0xFDF0F0, dark: 0x322323)
    static let magicWeak = adaptive(light: 0xF9F2EE, dark: 0x201F1F)

    // Layer and stroke
    static let layerBasement = adaptive(light: 0xF3F4F5, dark: 0x000000)
    static let layerDefault = adaptive(light: 0xFFFFFF, dark: 0x16171B)
    static let layerFill = adaptive(light: 0xF7F8F9, dark: 0x1D2025)
    static let layerFloating = adaptive(light: 0xFFFFFF, dark: 0x1D2025)
    static let neutralSolid = adaptive(light: 0x1A1C20, dark: 0x2B2E35)
    static let neutralSolidPressed = adaptive(light: 0x2A3038, dark: 0x393D46)
    static let neutralWeak = adaptive(light: 0xF3F4F5, dark: 0x2B2E35)
    static let neutralWeakPressed = adaptive(light: 0xEEEFF1, dark: 0x393D46)
    static let strokeSubtle = adaptive(light: 0xE6E7EA, dark: 0x2B2E35)
    static let strokeWeak = adaptive(light: 0xDCDEE3, dark: 0x393D46)

    static let magicGradient = LinearGradient(
        colors: [brandWeak, magicWeak, informativeWeak],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(seedRGB: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

enum SeedSpacing {
    static let x0_5: CGFloat = 2
    static let x1: CGFloat = 4
    static let x1_5: CGFloat = 6
    static let x2: CGFloat = 8
    static let x2_5: CGFloat = 10
    static let x3: CGFloat = 12
    static let x3_5: CGFloat = 14
    static let x4: CGFloat = 16
    static let x4_5: CGFloat = 18
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x7: CGFloat = 28
    static let x8: CGFloat = 32
    static let x9: CGFloat = 36
    static let x10: CGFloat = 40
    static let x12: CGFloat = 48
    static let x13: CGFloat = 52
    static let x14: CGFloat = 56
    static let x16: CGFloat = 64

    static let globalGutter = x4
    static let componentDefault = x3
    static let betweenText = x1_5
    static let screenBottom = x14
}

enum SeedRadius {
    static let r1: CGFloat = 4
    static let r2: CGFloat = 8
    static let r2_5: CGFloat = 10
    static let r3: CGFloat = 12
    static let r3_5: CGFloat = 14
    static let r4: CGFloat = 16
    static let r5: CGFloat = 20
    static let r6: CGFloat = 24
    static let full: CGFloat = 9_999
}

enum SeedTypography {
    static let pageTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let sectionTitle = Font.system(.title3, design: .default, weight: .bold)
    static let cardTitle = Font.system(.headline, design: .default, weight: .bold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let bodyMedium = Font.system(.body, design: .default, weight: .medium)
    static let caption = Font.system(.subheadline, design: .default, weight: .regular)
    static let captionBold = Font.system(.subheadline, design: .default, weight: .bold)
}

struct SeedActionButtonStyle: ButtonStyle {
    enum Variant {
        case brandSolid
        case neutralSolid
        case neutralWeak
        case ghost
        case criticalSolid
    }

    enum Size {
        case medium
        case large

        var minimumHeight: CGFloat {
            switch self {
            case .medium: 44
            case .large: SeedSpacing.x13
            }
        }

        var radius: CGFloat {
            switch self {
            case .medium: SeedRadius.r2_5
            case .large: SeedRadius.r3
            }
        }
    }

    let variant: Variant
    var size: Size = .large
    var expands: Bool = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SeedTypography.bodyMedium.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, SeedSpacing.x4)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minHeight: size.minimumHeight)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: size.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: size.radius, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return SeedColor.fgDisabled }

        switch variant {
        case .brandSolid, .neutralSolid, .criticalSolid:
            return SeedColor.fgInverted
        case .neutralWeak, .ghost:
            return SeedColor.fgNeutral
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return SeedColor.neutralWeak }

        switch variant {
        case .brandSolid:
            return isPressed ? SeedColor.brandPressed : SeedColor.brand
        case .neutralSolid:
            return isPressed ? SeedColor.neutralSolidPressed : SeedColor.neutralSolid
        case .neutralWeak:
            return isPressed ? SeedColor.neutralWeakPressed : SeedColor.neutralWeak
        case .ghost:
            return isPressed ? SeedColor.neutralWeakPressed : .clear
        case .criticalSolid:
            return isPressed ? SeedColor.criticalPressed : SeedColor.critical
        }
    }
}

struct SeedStatusBadge: View {
    enum Tone {
        case neutral
        case positive
        case informative
        case warning
        case critical

        var foreground: Color {
            switch self {
            case .neutral: SeedColor.fgMuted
            case .positive: SeedColor.positive
            case .informative: SeedColor.informative
            case .warning: SeedColor.warning
            case .critical: SeedColor.critical
            }
        }

        var background: Color {
            switch self {
            case .neutral: SeedColor.neutralWeak
            case .positive: SeedColor.positiveWeak
            case .informative: SeedColor.informativeWeak
            case .warning: SeedColor.warningWeak
            case .critical: SeedColor.criticalWeak
            }
        }
    }

    let title: String
    let tone: Tone

    var body: some View {
        HStack(spacing: SeedSpacing.x1_5) {
            Circle()
                .fill(tone.foreground)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, SeedSpacing.x2_5)
        .frame(minHeight: 28)
        .background(tone.background, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct SeedCallout: View {
    enum Tone {
        case neutral
        case informative
        case positive
        case warning
        case critical
        case magic

        var foreground: Color {
            switch self {
            case .neutral: SeedColor.fgMuted
            case .informative: SeedColor.informative
            case .positive: SeedColor.positive
            case .warning: SeedColor.warning
            case .critical: SeedColor.critical
            case .magic: SeedColor.brand
            }
        }

        var background: Color {
            switch self {
            case .neutral: SeedColor.neutralWeak
            case .informative: SeedColor.informativeWeak
            case .positive: SeedColor.positiveWeak
            case .warning: SeedColor.warningWeak
            case .critical: SeedColor.criticalWeak
            case .magic: SeedColor.magicWeak
            }
        }
    }

    let symbol: String
    let title: String?
    let description: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: SeedSpacing.x3) {
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.foreground)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SeedColor.fgNeutral)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(SeedColor.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SeedSpacing.x3_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.background, in: RoundedRectangle(cornerRadius: SeedRadius.r2_5, style: .continuous))
    }
}

struct LumiMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SeedColor.brand, SeedColor.informative],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.43, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SeedSurfaceModifier: ViewModifier {
    var radius: CGFloat = SeedRadius.r5
    var floating = false

    func body(content: Content) -> some View {
        content
            .background(
                floating ? SeedColor.layerFloating : SeedColor.layerDefault,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SeedColor.strokeSubtle, lineWidth: 0.5)
            }
            .shadow(
                color: floating ? Color.black.opacity(0.08) : .clear,
                radius: floating ? 10 : 0,
                y: floating ? 2 : 0
            )
    }
}

extension View {
    func seedSurface(radius: CGFloat = SeedRadius.r5, floating: Bool = false) -> some View {
        modifier(SeedSurfaceModifier(radius: radius, floating: floating))
    }
}

private extension UIColor {
    convenience init(seedRGB: UInt32) {
        let red = CGFloat((seedRGB >> 16) & 0xFF) / 255
        let green = CGFloat((seedRGB >> 8) & 0xFF) / 255
        let blue = CGFloat(seedRGB & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
