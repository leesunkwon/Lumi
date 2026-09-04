//
//  LumiOnboardingView.swift
//  MetaGemini
//

import SwiftUI

struct LumiOnboardingView: View {
    let onConnect: () -> Void
    let onSkip: () -> Void

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        .init(
            symbol: "sparkles",
            accent: SeedColor.brand,
            eyebrow: "LUMI를 만나보세요",
            title: "보고 묻고, 듣는 개인 AI 비서",
            detail: "Ray-Ban Meta 안경과 iPhone을 연결해 일상의 궁금증을 가장 자연스러운 방식으로 해결해요."
        ),
        .init(
            symbol: "waveform",
            accent: SeedColor.informative,
            eyebrow: "말하면 바로",
            title: "생각을 말로 정리해요",
            detail: "안경 마이크로 질문하면 Lumi가 핵심을 이해하고, 안경 스피커로 답을 들려드려요."
        ),
        .init(
            symbol: "camera.viewfinder",
            accent: SeedColor.warning,
            eyebrow: "눈앞의 장면",
            title: "지금 보는 것을 이해해요",
            detail: "메뉴, 물건, 문서처럼 궁금한 장면을 한 장 찍어 자연스럽게 설명받을 수 있어요."
        ),
        .init(
            symbol: "bookmark.fill",
            accent: SeedColor.positive,
            eyebrow: "사용자 메모리",
            title: "중요한 순간은 로컬에 남겨요",
            detail: "“이건 기억해줘”처럼 명확히 요청하면 핵심만 정리해 iPhone 안에 저장하고 나중에 다시 찾을 수 있어요."
        ),
        .init(
            symbol: "eyeglasses",
            accent: SeedColor.brand,
            eyebrow: "준비가 되었어요",
            title: "이제 안경을 연결할게요",
            detail: "Meta AI 앱으로 이동해 Lumi 사용을 승인합니다. 연결 전에 아래 내용을 확인해주세요."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressHeader

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    ScrollView {
                        pageContent(page, index: index)
                            .padding(.horizontal, SeedSpacing.x5)
                            .padding(.vertical, SeedSpacing.x5)
                    }
                    .scrollIndicators(.hidden)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            controls
        }
        .background(SeedColor.layerBasement)
    }

    private var topBar: some View {
        HStack(spacing: SeedSpacing.x2) {
            LumiMark(size: 32)
            Text("Lumi")
                .font(.headline.weight(.bold))
                .foregroundStyle(SeedColor.fgNeutral)

            Spacer()

            if currentPage < pages.count - 1 {
                Button("건너뛰기") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = pages.count - 1
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SeedColor.fgMuted)
            }
        }
        .padding(.horizontal, SeedSpacing.globalGutter)
        .padding(.vertical, SeedSpacing.x3)
        .background(SeedColor.layerDefault)
    }

    private var progressHeader: some View {
        HStack(spacing: SeedSpacing.x3) {
            Text("\(currentPage + 1) / \(pages.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(SeedColor.fgSubtle)
                .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SeedColor.neutralWeak)
                    Capsule()
                        .fill(pages[currentPage].accent)
                        .frame(width: proxy.size.width * CGFloat(currentPage + 1) / CGFloat(pages.count))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, SeedSpacing.globalGutter)
        .padding(.top, SeedSpacing.x3)
        .animation(.easeInOut(duration: 0.2), value: currentPage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("전체 \(pages.count)단계 중 \(currentPage + 1)단계")
    }

    private func pageContent(_ page: OnboardingPage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x6) {
            onboardingArtwork(page, index: index)

            VStack(alignment: .leading, spacing: SeedSpacing.x3) {
                Text(page.eyebrow)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(page.accent)

                Text(page.title)
                    .font(SeedTypography.pageTitle)
                    .foregroundStyle(SeedColor.fgNeutral)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.detail)
                    .font(SeedTypography.body)
                    .foregroundStyle(SeedColor.fgMuted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            onboardingPreview(index: index, accent: page.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func onboardingArtwork(_ page: OnboardingPage, index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: SeedRadius.r6, style: .continuous)
                .fill(SeedColor.magicGradient)

            Circle()
                .fill(page.accent.opacity(0.12))
                .frame(width: 164, height: 164)
                .offset(x: 92, y: -58)

            Circle()
                .fill(SeedColor.layerDefault.opacity(0.72))
                .frame(width: 112, height: 112)

            Image(systemName: page.symbol)
                .symbolVariant(.fill)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(page.accent)
                .contentTransition(.symbolEffect(.replace))

            Text(String(format: "%02d", index + 1))
                .font(.caption2.weight(.bold))
                .foregroundStyle(SeedColor.fgSubtle)
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(SeedSpacing.x4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .overlay {
            RoundedRectangle(cornerRadius: SeedRadius.r6, style: .continuous)
                .stroke(page.accent.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func onboardingPreview(index: Int, accent: Color) -> some View {
        switch index {
        case 0:
            HStack(spacing: SeedSpacing.x2) {
                previewChip("말하기", symbol: "waveform", color: SeedColor.informative)
                previewChip("장면 보기", symbol: "eye.fill", color: SeedColor.warning)
                previewChip("메모리", symbol: "bookmark.fill", color: SeedColor.positive)
            }
        case 1:
            HStack(spacing: SeedSpacing.x3) {
                HStack(alignment: .center, spacing: SeedSpacing.x1) {
                    ForEach([12, 20, 32, 22, 14], id: \.self) { height in
                        Capsule()
                            .fill(accent.opacity(0.78))
                            .frame(width: 4, height: CGFloat(height))
                    }
                }
                .frame(width: 68, height: 48)

                VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                    Text("버튼을 누르고 말해보세요")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SeedColor.fgNeutral)
                    Text("대답은 안경 스피커로 들려드려요")
                        .font(.caption)
                        .foregroundStyle(SeedColor.fgSubtle)
                }
                Spacer(minLength: 0)
            }
            .padding(SeedSpacing.x4)
            .seedSurface(radius: SeedRadius.r4)
        case 2:
            HStack(spacing: SeedSpacing.x3) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 64, height: 64)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous))

                VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                    Text("필요한 순간만 한 장")
                        .font(.subheadline.weight(.bold))
                    Text("사진은 사용자 메모리에 저장하지 않아요")
                        .font(.caption)
                        .foregroundStyle(SeedColor.fgSubtle)
                }
                Spacer(minLength: 0)
            }
            .padding(SeedSpacing.x4)
            .seedSurface(radius: SeedRadius.r4)
        case 3:
            HStack(alignment: .top, spacing: SeedSpacing.x3) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: SeedRadius.r2_5, style: .continuous))

                VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                    Text("다음 주 발표 아이디어")
                        .font(.subheadline.weight(.bold))
                    Text("핵심 메시지를 먼저 말하고 사례는 세 가지로 정리하기")
                        .font(.caption)
                        .foregroundStyle(SeedColor.fgMuted)
                        .lineLimit(2)
                    Text("방금 전")
                        .font(.caption2)
                        .foregroundStyle(SeedColor.fgSubtle)
                }
                Spacer(minLength: 0)
            }
            .padding(SeedSpacing.x4)
            .seedSurface(radius: SeedRadius.r4)
        default:
            VStack(alignment: .leading, spacing: SeedSpacing.x3) {
                connectionRequirement("Meta AI 앱이 설치되어 있어요", symbol: "app.badge")
                connectionRequirement("안경을 켜고 착용해주세요", symbol: "eyeglasses")
                connectionRequirement("Bluetooth 연결을 확인해주세요", symbol: "antenna.radiowaves.left.and.right")
            }
            .padding(SeedSpacing.x4)
            .seedSurface(radius: SeedRadius.r4)
        }
    }

    private func previewChip(_ title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: SeedSpacing.x2) {
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(SeedColor.fgMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SeedSpacing.x3)
        .seedSurface(radius: SeedRadius.r3)
    }

    private func connectionRequirement(_ title: String, symbol: String) -> some View {
        HStack(spacing: SeedSpacing.x3) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SeedColor.brand)
                .frame(width: 28, height: 28)
                .background(SeedColor.brandWeak, in: Circle())
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SeedColor.fgNeutral)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: SeedSpacing.x3) {
            if currentPage == pages.count - 1 {
                Button(action: onConnect) {
                    Label("Meta AI에서 연결 시작", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(SeedActionButtonStyle(variant: .brandSolid))

                Button("나중에 연결할게요", action: onSkip)
                    .buttonStyle(SeedActionButtonStyle(variant: .ghost, size: .medium))
            } else {
                HStack(spacing: SeedSpacing.x3) {
                    if currentPage > 0 {
                        Button("이전") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentPage -= 1
                            }
                        }
                        .buttonStyle(
                            SeedActionButtonStyle(
                                variant: .neutralWeak,
                                size: .large,
                                expands: false
                            )
                        )
                    }

                    Button("다음") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(SeedActionButtonStyle(variant: .brandSolid))
                }
            }
        }
        .padding(.horizontal, SeedSpacing.globalGutter)
        .padding(.top, SeedSpacing.x3)
        .padding(.bottom, SeedSpacing.x2)
        .background(SeedColor.layerDefault)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct OnboardingPage {
    let symbol: String
    let accent: Color
    let eyebrow: String
    let title: String
    let detail: String
}
