//
//  ContentView.swift
//  MetaGemini
//
//  Created by sunkwon on 8/29/26.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: LumiViewModel

    @AppStorage("lumi.hasSeenIntro") private var hasSeenIntro = false
    @State private var selectedTab = LumiTab.assistant
    @State private var hasSavedLatestAnswer = false

    var body: some View {
        Group {
            if hasSeenIntro {
                appTabs
            } else {
                LumiOnboardingView(
                    onConnect: {
                        hasSeenIntro = true
                        viewModel.connectGlasses()
                    },
                    onSkip: {
                        hasSeenIntro = true
                    }
                )
            }
        }
        .tint(SeedColor.brand)
        .alert("Lumi", isPresented: $viewModel.isShowingError) {
            Button("확인", role: .cancel) {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.lastAnswer) {
            hasSavedLatestAnswer = false
        }
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            assistantDashboard
                .tabItem {
                    Label("Lumi", systemImage: "sparkles")
                }
                .tag(LumiTab.assistant)

            memoriesScreen
                .tabItem {
                    Label("기억", systemImage: "bookmark")
                }
                .tag(LumiTab.memories)
        }
        .toolbarBackground(SeedColor.layerDefault, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var assistantDashboard: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: SeedSpacing.x6) {
                    voiceHero

                    if let answer = viewModel.lastAnswer {
                        answerCard(answer)
                    }

                    quickActionsSection
                    recentMemoriesSection
                }
                .padding(.horizontal, SeedSpacing.globalGutter)
                .padding(.top, SeedSpacing.x3)
                .padding(.bottom, SeedSpacing.screenBottom)
            }
            .scrollIndicators(.hidden)
            .background(SeedColor.layerBasement)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: SeedSpacing.x2) {
                        LumiMark(size: 28)
                        Text("Lumi")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(SeedColor.fgNeutral)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    settingsMenu
                }
            }
        }
    }

    private var voiceHero: some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x5) {
            HStack(alignment: .center) {
                SeedStatusBadge(title: heroStatusTitle, tone: heroStatusTone)
                Spacer()
                Image(systemName: "eyeglasses")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(heroAccent)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: SeedSpacing.betweenText) {
                Text(heroEyebrow)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(heroAccent)

                Text(heroTitle)
                    .font(SeedTypography.pageTitle)
                    .foregroundStyle(SeedColor.fgNeutral)
                    .fixedSize(horizontal: false, vertical: true)

                Text(heroDetail)
                    .font(SeedTypography.body)
                    .foregroundStyle(SeedColor.fgMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            voiceWaveform

            Button(action: performVoiceAction) {
                HStack(spacing: SeedSpacing.x2) {
                    if isVoiceActionLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: voiceButtonIcon)
                            .symbolVariant(.fill)
                    }
                    Text(voiceButtonTitle)
                }
            }
            .buttonStyle(
                SeedActionButtonStyle(
                    variant: viewModel.isRecording ? .criticalSolid : .brandSolid
                )
            )
            .disabled(isVoiceActionDisabled)
            .accessibilityLabel(voiceButtonTitle)
            .accessibilityHint(voiceButtonAccessibilityHint)
            .accessibilityValue(heroStatusTitle)
        }
        .padding(SeedSpacing.x5)
        .background {
            RoundedRectangle(cornerRadius: SeedRadius.r6, style: .continuous)
                .fill(SeedColor.magicGradient)
                .overlay {
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: SeedRadius.r6, style: .continuous)
                            .fill(SeedColor.criticalWeak.opacity(0.92))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: SeedRadius.r6, style: .continuous)
                .stroke(heroAccent.opacity(0.14), lineWidth: 1)
        }
    }

    private var voiceWaveform: some View {
        HStack(alignment: .center, spacing: SeedSpacing.x1_5) {
            ForEach(Array([12, 20, 32, 44, 30, 22, 14].enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(heroAccent.opacity(index == 3 ? 1 : 0.45))
                    .frame(width: 5, height: CGFloat(height))
            }

            Spacer()

            Text(waveformDetail)
                .font(.caption)
                .foregroundStyle(SeedColor.fgSubtle)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityHidden(true)
    }

    private func answerCard(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x4) {
            HStack(spacing: SeedSpacing.x2_5) {
                LumiMark(size: 34)

                VStack(alignment: .leading, spacing: SeedSpacing.x0_5) {
                    Text("Lumi의 답변")
                        .font(SeedTypography.cardTitle)
                    Text("방금 나눈 대화")
                        .font(.caption)
                        .foregroundStyle(SeedColor.fgSubtle)
                }

                Spacer()

                SeedStatusBadge(title: "새 답변", tone: .informative)
            }

            if let transcript = viewModel.lastTranscript, !transcript.isEmpty {
                HStack(alignment: .top, spacing: SeedSpacing.x2) {
                    Image(systemName: "quote.opening")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SeedColor.brand)
                    Text(transcript)
                        .font(.subheadline)
                        .foregroundStyle(SeedColor.fgMuted)
                }
                .padding(SeedSpacing.x3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SeedColor.layerFill, in: RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous))
            }

            Text(answer)
                .font(SeedTypography.body)
                .foregroundStyle(SeedColor.fgNeutral)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.saveLatestAnswerAsMemo()
                withAnimation(.easeOut(duration: 0.2)) {
                    hasSavedLatestAnswer = true
                }
            } label: {
                Label(
                    hasSavedLatestAnswer ? "기억에 저장했어요" : "답변을 기억에 저장",
                    systemImage: hasSavedLatestAnswer ? "checkmark" : "bookmark"
                )
            }
            .buttonStyle(SeedActionButtonStyle(variant: .neutralWeak, size: .medium))
            .disabled(hasSavedLatestAnswer)
        }
        .padding(SeedSpacing.x4)
        .seedSurface()
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x3) {
            sectionHeader(title: "빠르게 시작", detail: "안경 카메라로 눈앞의 장면을 이해해요")

            VStack(alignment: .leading, spacing: SeedSpacing.x4) {
                HStack(alignment: .top, spacing: SeedSpacing.x3) {
                    iconTile(symbol: "camera.viewfinder", color: SeedColor.informative)

                    VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                        Text("장면 보기")
                            .font(SeedTypography.cardTitle)
                            .foregroundStyle(SeedColor.fgNeutral)
                        Text("사진 한 장을 찍어 메뉴, 문서, 주변 장면을 설명해요.")
                            .font(SeedTypography.caption)
                            .foregroundStyle(SeedColor.fgMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: performSceneAction) {
                    HStack(spacing: SeedSpacing.x2) {
                        if viewModel.isCapturingScene {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: viewModel.isGlassesAvailable ? "eye.fill" : "eyeglasses")
                        }
                        Text(sceneButtonTitle)
                    }
                }
                .buttonStyle(SeedActionButtonStyle(variant: .neutralSolid))
                .disabled(viewModel.isBusy || viewModel.isRegistering)
                .accessibilityHint(
                    viewModel.isGlassesAvailable
                        ? "안경 카메라로 사진을 촬영해 Gemini에 설명을 요청합니다."
                        : "Meta AI 앱에서 안경 연결을 시작합니다."
                )

                SeedCallout(
                    symbol: "lock.shield",
                    title: "사진은 한 장만 사용해요",
                    description: "장면 설명에 필요한 순간만 촬영하고, 사진을 메모에 저장하지 않아요.",
                    tone: .informative
                )
            }
            .padding(SeedSpacing.x4)
            .seedSurface()
        }
    }

    private var recentMemoriesSection: some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x3) {
            HStack(alignment: .bottom) {
                sectionHeader(title: "최근 기억", detail: "Lumi와 남긴 메모")
                Spacer()
                Button("전체 보기") {
                    selectedTab = .memories
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SeedColor.brand)
            }

            if viewModel.memos.isEmpty {
                SeedCallout(
                    symbol: "bookmark",
                    title: "아직 기억한 내용이 없어요",
                    description: "답변을 저장하거나 “기억해줘”라고 말하면 여기에 모아드려요.",
                    tone: .neutral
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.memos.prefix(2).enumerated()), id: \.element.id) { index, memo in
                        memoryRow(memo)

                        if index < min(viewModel.memos.count, 2) - 1 {
                            Divider()
                                .padding(.leading, SeedSpacing.x12)
                        }
                    }
                }
                .seedSurface(radius: SeedRadius.r4)
            }
        }
    }

    private var memoriesScreen: some View {
        NavigationStack {
            VStack(spacing: 0) {
                memorySearchField
                    .padding(.horizontal, SeedSpacing.globalGutter)
                    .padding(.vertical, SeedSpacing.x3)
                    .background(SeedColor.layerDefault)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SeedSpacing.x4) {
                        SeedCallout(
                            symbol: "iphone.gen3",
                            title: "이 iPhone에만 저장돼요",
                            description: "Lumi의 메모는 기본적으로 기기 안에 보관돼요.",
                            tone: .positive
                        )

                        memoryContent
                    }
                    .padding(.horizontal, SeedSpacing.globalGutter)
                    .padding(.top, SeedSpacing.x2)
                    .padding(.bottom, SeedSpacing.screenBottom)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
            .background(SeedColor.layerBasement)
            .navigationTitle("기억")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    settingsMenu
                }
            }
        }
    }

    private var memorySearchField: some View {
        HStack(spacing: SeedSpacing.x2_5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SeedColor.fgSubtle)

            TextField("메모 검색", text: $viewModel.memoSearchQuery)
                .textInputAutocapitalization(.never)

            if !viewModel.memoSearchQuery.isEmpty {
                Button {
                    viewModel.memoSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SeedColor.fgSubtle)
                }
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, SeedSpacing.x3)
        .frame(minHeight: 44)
        .background(SeedColor.layerFill, in: RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous))
    }

    @ViewBuilder
    private var memoryContent: some View {
        if viewModel.memos.isEmpty {
            emptyMemoryState(
                symbol: "bookmark",
                title: "아직 기억한 메모가 없어요",
                detail: "음성 질문에서 “기억해줘”라고 말하거나 Lumi의 답변을 저장해보세요."
            )
        } else if viewModel.filteredMemos.isEmpty {
            VStack(spacing: SeedSpacing.x4) {
                emptyMemoryState(
                    symbol: "magnifyingglass",
                    title: "검색 결과가 없어요",
                    detail: "다른 검색어로 다시 찾아보세요."
                )

                Button("검색어 지우기") {
                    viewModel.memoSearchQuery = ""
                }
                .buttonStyle(SeedActionButtonStyle(variant: .neutralWeak, size: .medium))
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("메모 (viewModel.filteredMemos.count)개")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SeedColor.fgMuted)
                    Spacer()
                }
                .padding(.horizontal, SeedSpacing.x4)
                .padding(.vertical, SeedSpacing.x3)

                Divider()

                ForEach(Array(viewModel.filteredMemos.enumerated()), id: \.element.id) { index, memo in
                    memoryRow(memo)

                    if index < viewModel.filteredMemos.count - 1 {
                        Divider()
                            .padding(.leading, SeedSpacing.x12)
                    }
                }
            }
            .seedSurface(radius: SeedRadius.r4)
        }
    }

    private func memoryRow(_ memo: VoiceMemo) -> some View {
        HStack(alignment: .top, spacing: SeedSpacing.x3) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedColor.brand)
                .frame(width: 36, height: 36)
                .background(SeedColor.brandWeak, in: RoundedRectangle(cornerRadius: SeedRadius.r2_5, style: .continuous))

            VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                Text(memo.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SeedColor.fgNeutral)

                Text(memo.body)
                    .font(.subheadline)
                    .foregroundStyle(SeedColor.fgMuted)
                    .lineLimit(3)

                Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(SeedColor.fgSubtle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SeedSpacing.x3)
        .padding(.vertical, SeedSpacing.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func emptyMemoryState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: SeedSpacing.x4) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(SeedColor.brand)
                .frame(width: 64, height: 64)
                .background(SeedColor.brandWeak, in: RoundedRectangle(cornerRadius: SeedRadius.r5, style: .continuous))

            VStack(spacing: SeedSpacing.betweenText) {
                Text(title)
                    .font(SeedTypography.cardTitle)
                    .foregroundStyle(SeedColor.fgNeutral)
                Text(detail)
                    .font(SeedTypography.caption)
                    .foregroundStyle(SeedColor.fgMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SeedSpacing.x5)
        .padding(.vertical, SeedSpacing.x10)
        .seedSurface()
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x0_5) {
            Text(title)
                .font(SeedTypography.sectionTitle)
                .foregroundStyle(SeedColor.fgNeutral)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(SeedColor.fgSubtle)
        }
    }

    private func iconTile(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous))
            .accessibilityHidden(true)
    }

    private var settingsMenu: some View {
        Menu {
            if !viewModel.isGlassesAvailable {
                Button {
                    viewModel.connectGlasses()
                } label: {
                    Label("안경 연결", systemImage: "eyeglasses")
                }
                .disabled(viewModel.isRegistering)
            }

            Button {
                hasSeenIntro = false
            } label: {
                Label("Lumi 소개 다시 보기", systemImage: "rectangle.on.rectangle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(SeedColor.fgNeutral)
        }
        .accessibilityLabel("Lumi 메뉴")
    }

    private func performVoiceAction() {
        if viewModel.isGlassesAvailable {
            viewModel.toggleVoiceQuestion()
        } else {
            viewModel.connectGlasses()
        }
    }

    private func performSceneAction() {
        if viewModel.isGlassesAvailable {
            viewModel.describeScene()
        } else {
            viewModel.connectGlasses()
        }
    }

    private var heroEyebrow: String {
        if viewModel.isRecording { return "LUMI가 듣고 있어요" }
        if viewModel.isSpeaking { return "LUMI가 답하고 있어요" }
        if viewModel.isProcessing { return "GEMINI와 생각하는 중" }
        if viewModel.isCapturingScene { return "눈앞의 장면을 보는 중" }
        if viewModel.isGlassesAvailable { return "보고 묻고, 듣는 개인 비서" }
        return "RAY-BAN META와 시작하기"
    }

    private var heroTitle: String {
        if viewModel.isRecording { return "무엇이든\n말해보세요" }
        if viewModel.isStartingVoice { return "마이크를\n준비하고 있어요" }
        if viewModel.isSpeaking { return "답변을\n들려드리고 있어요" }
        if viewModel.isProcessing { return "답을\n생각하고 있어요" }
        if viewModel.isCapturingScene { return "장면을\n살펴보고 있어요" }
        if viewModel.isGlassesAvailable { return "지금 궁금한 걸\n물어보세요" }
        return "안경과 Lumi를\n연결해볼까요?"
    }

    private var heroDetail: String {
        if viewModel.isRecording { return "질문을 마치면 아래 버튼을 한 번 더 눌러 전송하세요." }
        if viewModel.isStartingVoice { return "안경 마이크로 음성 경로를 연결하고 있어요." }
        if viewModel.isSpeaking { return "Gemini가 만든 자연스러운 한국어 음성을 안경 스피커로 재생하고 있어요." }
        if viewModel.isProcessing { return "질문을 이해하고 가장 도움이 되는 답을 준비하고 있어요." }
        if viewModel.isCapturingScene { return "촬영한 한 장의 사진에서 필요한 정보를 찾고 있어요." }
        if viewModel.isGlassesAvailable { return "버튼을 누르고 안경에 대고 말하면 답을 귀로 들려드려요." }
        return "한 번 연결하면 음성 질문과 장면 설명을 바로 사용할 수 있어요."
    }

    private var heroStatusTitle: String {
        if viewModel.isRecording { return "듣는 중" }
        if viewModel.isSpeaking { return "답변 재생 중" }
        if viewModel.isProcessing || viewModel.isStartingVoice { return "답변 준비 중" }
        if viewModel.isCapturingScene { return "장면 분석 중" }
        if viewModel.isGlassesAvailable { return "안경 준비됨" }
        if viewModel.isRegistering { return "연결 중" }
        return "시작 전"
    }

    private var heroStatusTone: SeedStatusBadge.Tone {
        if viewModel.isRecording { return .critical }
        if viewModel.isSpeaking { return .positive }
        if viewModel.isProcessing || viewModel.isStartingVoice || viewModel.isCapturingScene { return .informative }
        if viewModel.isGlassesAvailable { return .positive }
        if viewModel.isRegistering { return .warning }
        return .neutral
    }

    private var heroAccent: Color {
        viewModel.isRecording ? SeedColor.critical : SeedColor.brand
    }

    private var voiceButtonTitle: String {
        if viewModel.isRecording { return "질문 보내기" }
        if viewModel.isStartingVoice { return "마이크 준비 중" }
        if viewModel.isSpeaking { return "답변 재생 중" }
        if viewModel.isProcessing { return "답변 준비 중" }
        if viewModel.isRegistering { return "Meta AI 연결 중" }
        if viewModel.isGlassesAvailable { return "음성으로 질문하기" }
        return "안경 연결 시작"
    }

    private var voiceButtonIcon: String {
        if viewModel.isRecording { return "stop.fill" }
        if viewModel.isGlassesAvailable { return "mic.fill" }
        return "eyeglasses"
    }

    private var isVoiceActionLoading: Bool {
        viewModel.isStartingVoice || viewModel.isProcessing || viewModel.isSpeaking || viewModel.isRegistering
    }

    private var isVoiceActionDisabled: Bool {
        viewModel.isStartingVoice
            || viewModel.isProcessing
            || viewModel.isCapturingScene
            || viewModel.isSpeaking
            || viewModel.isRegistering
    }

    private var voiceButtonAccessibilityHint: String {
        if viewModel.isRecording { return "녹음을 멈추고 질문을 Gemini에 전송합니다." }
        if viewModel.isGlassesAvailable { return "안경 마이크로 음성 녹음을 시작합니다." }
        return "Meta AI 앱에서 Lumi와 안경의 연결을 시작합니다."
    }

    private var sceneButtonTitle: String {
        if viewModel.isCapturingScene { return "장면을 살펴보는 중" }
        if viewModel.isSpeaking { return "답변을 들려드리는 중" }
        if viewModel.isGlassesAvailable { return "지금 보는 장면 설명" }
        return "안경 연결하고 시작"
    }

    private var waveformDetail: String {
        if viewModel.isRecording { return "질문이 끝나면 한 번 더 눌러주세요" }
        if viewModel.isSpeaking { return "따뜻한 Gemini 음성으로 답하고 있어요" }
        return "안경 마이크로 자연스럽게 말해보세요"
    }
}

private enum LumiTab: Hashable {
    case assistant
    case memories
}

#Preview {
    ContentView(viewModel: .preview)
}
