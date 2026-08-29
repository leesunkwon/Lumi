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
    @State private var conversationPath: [UUID] = []
    @ScaledMetric(relativeTo: .largeTitle) private var homeTitleSize: CGFloat = 34

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

            conversationsScreen
                .tabItem {
                    Label("대화", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(LumiTab.conversations)

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
                LazyVStack(spacing: 0) {
                    deviceOverview
                        .padding(.horizontal, SeedSpacing.globalGutter)

                    LazyVStack(spacing: SeedSpacing.x6) {
                        if let answer = viewModel.lastAnswer {
                            answerCard(answer)
                        }

                        recentMemoriesSection
                    }
                    .padding(.horizontal, SeedSpacing.globalGutter)
                    .padding(.top, SeedSpacing.x6)
                    .padding(.bottom, SeedSpacing.screenBottom)
                }
            }
            .scrollIndicators(.hidden)
            .background(SeedColor.layerDefault)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var conversationsScreen: some View {
        NavigationStack(path: $conversationPath) {
            ScrollView {
                LazyVStack(spacing: SeedSpacing.x3) {
                    ForEach(viewModel.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            conversationRow(conversation)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SeedSpacing.globalGutter)
                .padding(.top, SeedSpacing.x3)
                .padding(.bottom, SeedSpacing.screenBottom)
            }
            .scrollIndicators(.hidden)
            .background(SeedColor.layerDefault)
            .navigationTitle("대화")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { conversationID in
                ConversationDetailView(
                    viewModel: viewModel,
                    conversationID: conversationID
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let conversationID = viewModel.startNewConversation()
                        conversationPath.append(conversationID)
                    } label: {
                        Label("새 세션", systemImage: "square.and.pencil")
                    }
                    .accessibilityHint("새로운 대화 세션을 만들고 엽니다.")
                }
            }
        }
    }

    private func conversationRow(_ conversation: ConversationSession) -> some View {
        HStack(alignment: .top, spacing: SeedSpacing.x3) {
            LumiMark(size: 38)

            VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                HStack(spacing: SeedSpacing.x2) {
                    Text(conversation.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(SeedColor.fgNeutral)
                        .lineLimit(1)

                    if conversation.id == viewModel.activeConversationID {
                        Text("현재")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(SeedColor.brand)
                    }
                }

                Text(conversation.preview)
                    .font(.subheadline)
                    .foregroundStyle(SeedColor.fgMuted)
                    .lineLimit(2)

                Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(SeedColor.fgSubtle)
            }

            Spacer(minLength: SeedSpacing.x2)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SeedColor.fgSubtle)
                .padding(.top, SeedSpacing.x1)
        }
        .padding(SeedSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedColor.layerFill, in: RoundedRectangle(cornerRadius: SeedRadius.r4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SeedRadius.r4, style: .continuous)
                .stroke(SeedColor.strokeSubtle, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("이 대화를 현재 세션으로 선택하고 내용을 확인합니다.")
    }

    private var deviceOverview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lumi")
                    .font(.system(size: homeTitleSize, weight: .bold, design: .default))
                    .foregroundStyle(SeedColor.fgNeutral)
                    .lineLimit(1)

                Spacer()

                settingsMenu
            }
            .padding(.top, SeedSpacing.x2)

            Image("RayBanMetaGlasses")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 260)
                .offset(y: -18)
                .frame(height: 128)
                .clipped()
                .padding(.top, SeedSpacing.x2)
                .accessibilityHidden(true)

            connectionStatus
                .padding(.top, SeedSpacing.x1)

            if shouldShowActivityDetail {
                Text(voiceActivityDetail)
                    .font(.footnote)
                    .foregroundStyle(viewModel.isRecording ? SeedColor.critical : SeedColor.fgSubtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SeedSpacing.x2)
            }

            if viewModel.isGlassesAvailable {
                HStack(spacing: SeedSpacing.x7) {
                    deviceActionButton(
                        symbol: "camera",
                        label: sceneButtonTitle,
                        hint: "안경 카메라로 사진 한 장을 촬영해 장면을 설명합니다.",
                        isLoading: viewModel.isCapturingScene,
                        isDisabled: viewModel.isBusy || viewModel.isRegistering,
                        action: performSceneAction
                    )

                    deviceActionButton(
                        symbol: voiceActionSymbol,
                        label: voiceButtonTitle,
                        hint: voiceButtonAccessibilityHint,
                        isLoading: isVoiceActionLoading,
                        isDisabled: isVoiceActionDisabled,
                        isPrimary: true,
                        isCritical: viewModel.isRecording,
                        action: performVoiceAction
                    )
                }
                .padding(.top, SeedSpacing.x7)
            } else {
                Button(action: performVoiceAction) {
                    HStack(spacing: SeedSpacing.x2) {
                        if viewModel.isRegistering {
                            ProgressView()
                                .tint(SeedColor.fgSubtle)
                        } else {
                            Image(systemName: "link")
                        }
                        Text(viewModel.isRegistering ? "연결 중" : "안경 연결")
                    }
                }
                .buttonStyle(SeedActionButtonStyle(variant: .neutralSolid))
                .disabled(viewModel.isRegistering)
                .padding(.top, SeedSpacing.x10)
                .accessibilityHint("Meta AI 앱에서 Lumi와 안경의 연결을 시작합니다.")
            }

            if viewModel.isGlassesAvailable {
                HStack(alignment: .top, spacing: SeedSpacing.x1_5) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .frame(width: 12, height: 12)

                    Text("장면 사진은 설명 후 저장하지 않아요.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(SeedColor.fgSubtle)
                .padding(.top, SeedSpacing.x4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, SeedSpacing.x6)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        HStack(spacing: SeedSpacing.x1_5) {
            if viewModel.isRegistering {
                ProgressView()
                    .controlSize(.mini)
                    .tint(SeedColor.brand)
            } else {
                Circle()
                    .fill(viewModel.isGlassesAvailable ? SeedColor.positive : SeedColor.fgSubtle)
                    .frame(width: 7, height: 7)
            }

            Text("Ray-Ban Meta")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SeedColor.fgNeutral)

            Text(deviceConnectionTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SeedColor.fgMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ray-Ban Meta")
        .accessibilityValue(deviceConnectionTitle)
    }

    private func deviceActionButton(
        symbol: String,
        label: String,
        hint: String,
        isLoading: Bool,
        isDisabled: Bool,
        isPrimary: Bool = false,
        isCritical: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isDisabled
                            ? SeedColor.neutralWeak
                            : (isCritical ? SeedColor.critical : (isPrimary ? SeedColor.brand : SeedColor.neutralWeak))
                    )

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(
                            isDisabled
                                ? SeedColor.fgSubtle
                                : (isPrimary || isCritical ? .white : SeedColor.fgNeutral)
                        )
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(
                            isDisabled
                                ? SeedColor.fgDisabled
                                : (isPrimary || isCritical ? SeedColor.fgInverted : SeedColor.fgNeutral)
                        )
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
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
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(SeedColor.fgNeutral)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("설정")
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

    private var shouldShowActivityDetail: Bool {
        !viewModel.isGlassesAvailable || viewModel.isBusy || viewModel.isRegistering
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
        if viewModel.isStartingVoice { return "준비 중" }
        if viewModel.isSpeaking { return "재생 중" }
        if viewModel.isProcessing { return "답변 준비 중" }
        if viewModel.isRegistering { return "연결 중" }
        if viewModel.isGlassesAvailable { return "음성 질문" }
        return "안경 연결 시작"
    }

    private var voiceActionSymbol: String {
        if viewModel.isRecording { return "stop.fill" }
        return "mic.fill"
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
        if viewModel.isCapturingScene { return "보는 중" }
        return "장면 보기"
    }

}

private struct ConversationDetailView: View {
    @Bindable var viewModel: LumiViewModel
    let conversationID: UUID

    private let bottomAnchor = "conversation-bottom"

    private var conversation: ConversationSession? {
        viewModel.conversation(for: conversationID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let conversation {
                    LazyVStack(spacing: SeedSpacing.x4) {
                        if conversation.messages.isEmpty {
                            emptyConversationState
                        } else {
                            ForEach(conversation.messages) { message in
                                messageBubble(message)
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                    .padding(.horizontal, SeedSpacing.globalGutter)
                    .padding(.top, SeedSpacing.x4)
                    .padding(.bottom, SeedSpacing.screenBottom)
                } else {
                    ContentUnavailableView(
                        "대화를 찾을 수 없어요",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("대화 목록에서 다시 선택해주세요.")
                    )
                    .padding(.top, SeedSpacing.x16)
                }
            }
            .scrollIndicators(.hidden)
            .background(SeedColor.layerDefault)
            .onAppear {
                viewModel.selectConversation(conversationID)
                scrollToLatestMessage(with: proxy)
            }
            .onChange(of: conversation?.messages) {
                scrollToLatestMessage(with: proxy)
            }
        }
        .navigationTitle(conversation?.title ?? "대화")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyConversationState: some View {
        VStack(spacing: SeedSpacing.x3) {
            LumiMark(size: 48)
            Text("새 대화가 준비됐어요")
                .font(.headline.weight(.bold))
                .foregroundStyle(SeedColor.fgNeutral)
            Text("Lumi 탭에서 안경 버튼으로 질문하면 이 대화에 계속 쌓여요.")
                .font(.subheadline)
                .foregroundStyle(SeedColor.fgMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SeedSpacing.x14)
        .padding(.horizontal, SeedSpacing.x5)
    }

    private func messageBubble(_ message: ConversationMessage) -> some View {
        HStack(alignment: .bottom, spacing: SeedSpacing.x2) {
            if message.role == .assistant {
                LumiMark(size: 28)
            } else {
                Spacer(minLength: SeedSpacing.x12)
            }

            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: SeedSpacing.x1
            ) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? SeedColor.fgInverted : SeedColor.fgNeutral)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SeedSpacing.x3)
                    .padding(.vertical, SeedSpacing.x2_5)
                    .background(
                        message.role == .user ? SeedColor.brand : SeedColor.layerFill,
                        in: RoundedRectangle(cornerRadius: SeedRadius.r4, style: .continuous)
                    )

                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(SeedColor.fgSubtle)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: SeedSpacing.x12)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "내 메시지" : "Lumi 메시지")
    }

    private func scrollToLatestMessage(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}

private enum LumiTab: Hashable {
    case assistant
    case conversations
    case memories
}

#Preview {
    ContentView(viewModel: .preview)
}
