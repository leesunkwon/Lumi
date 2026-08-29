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
                    deviceOverview

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
            .navigationTitle("Lumi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    settingsMenu
                }
            }
        }
    }

    private var deviceOverview: some View {
        VStack(spacing: SeedSpacing.x4) {
            Image("RayBanMetaGlasses")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 360)
                .scaleEffect(1.08)
                .offset(y: -22)
                .frame(height: 165)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: SeedSpacing.x1) {
                Text("Ray-Ban Meta")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SeedColor.fgNeutral)

                connectionStatus
            }

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
                    variant: viewModel.isRecording ? .criticalSolid : .neutralSolid
                )
            )
            .disabled(isVoiceActionDisabled)
            .accessibilityLabel(voiceButtonTitle)
            .accessibilityHint(voiceButtonAccessibilityHint)
            .accessibilityValue(deviceConnectionTitle)

            Text(voiceActivityDetail)
                .font(.footnote)
                .foregroundStyle(viewModel.isRecording ? SeedColor.critical : SeedColor.fgSubtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SeedSpacing.x2)
        .padding(.bottom, SeedSpacing.x2)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        HStack(spacing: SeedSpacing.x1_5) {
            if viewModel.isRegistering {
                ProgressView()
                    .controlSize(.mini)
                    .tint(deviceConnectionColor)
            } else {
                Circle()
                    .fill(deviceConnectionColor)
                    .frame(width: 8, height: 8)
            }

            Text(deviceConnectionTitle)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(deviceConnectionColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("안경 연결 상태")
        .accessibilityValue(deviceConnectionTitle)
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
            sectionHeader(title: "카메라", detail: "안경으로 지금 보고 있는 장면을 이해해요")

            Button(action: performSceneAction) {
                HStack(alignment: .top, spacing: SeedSpacing.x3) {
                    iconTile(symbol: "camera.viewfinder", color: SeedColor.informative)

                    VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                        Text(sceneButtonTitle)
                            .font(SeedTypography.cardTitle)
                            .foregroundStyle(SeedColor.fgNeutral)
                        Text("사진 한 장을 찍어 메뉴, 문서, 주변 장면을 설명해요.")
                            .font(SeedTypography.caption)
                            .foregroundStyle(SeedColor.fgMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: SeedSpacing.x2)

                    if viewModel.isCapturingScene {
                        ProgressView()
                            .tint(SeedColor.fgSubtle)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SeedColor.fgSubtle)
                    }
                }
                .padding(SeedSpacing.x4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy || viewModel.isRegistering)
            .seedSurface(radius: SeedRadius.r4)
            .accessibilityHint(
                viewModel.isGlassesAvailable
                    ? "안경 카메라로 사진을 촬영해 Gemini에 설명을 요청합니다."
                    : "Meta AI 앱에서 안경 연결을 시작합니다."
            )

            HStack(alignment: .top, spacing: SeedSpacing.x2) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(SeedColor.fgSubtle)
                    .frame(width: 16, height: 16)

                Text("사진은 장면 설명에만 사용하며 기기에 저장하지 않아요.")
                    .font(.footnote)
                    .foregroundStyle(SeedColor.fgSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SeedSpacing.x2)
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

    private var deviceConnectionTitle: String {
        if viewModel.isRegistering { return "연결 중" }
        if viewModel.isGlassesAvailable { return "연결됨" }
        return "연결 필요"
    }

    private var deviceConnectionColor: Color {
        if viewModel.isRegistering { return SeedColor.brand }
        if viewModel.isGlassesAvailable { return SeedColor.positive }
        return SeedColor.fgSubtle
    }

    private var voiceActivityDetail: String {
        if viewModel.isRecording { return "듣고 있어요. 질문이 끝나면 버튼을 한 번 더 눌러주세요." }
        if viewModel.isStartingVoice { return "안경 마이크를 준비하고 있어요." }
        if viewModel.isSpeaking { return "안경 스피커로 답변을 들려드리고 있어요." }
        if viewModel.isProcessing { return "답변을 준비하고 있어요." }
        if viewModel.isCapturingScene { return "안경 카메라로 장면을 살펴보고 있어요." }
        if viewModel.isRegistering { return "Meta AI에서 안경 연결을 마무리해주세요." }
        if viewModel.isGlassesAvailable { return "버튼을 누르고 안경에 대고 말해보세요." }
        return "먼저 Ray-Ban Meta를 Lumi에 연결해주세요."
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

}

private enum LumiTab: Hashable {
    case assistant
    case memories
}

#Preview {
    ContentView(viewModel: .preview)
}
