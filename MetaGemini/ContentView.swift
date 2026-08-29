//
//  ContentView.swift
//  MetaGemini
//
//  Created by sunkwon on 8/29/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Bindable var viewModel: LumiViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lumi.hasSeenIntro") private var hasSeenIntro = false
    @State private var selectedTab = LumiTab.assistant
    @State private var hasSavedLatestAnswer = false
    @State private var isAnswerIslandExpanded = true
    @State private var dashboardEntranceStage = 0
    @State private var hasPlayedDashboardEntrance = false
    @State private var conversationPath: [UUID] = []
    @State private var memoryPendingDeletion: VoiceMemo?
    @State private var memoryEditor: UserMemoryEditor?
    @State private var isShowingClearAllMemoriesConfirmation = false
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
        .confirmationDialog(
            "사용자 메모리를 삭제할까요?",
            isPresented: Binding(
                get: { memoryPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        memoryPendingDeletion = nil
                    }
                }
            ),
            presenting: memoryPendingDeletion
        ) { memory in
            Button("삭제", role: .destructive) {
                viewModel.deleteUserMemory(id: memory.id)
                memoryPendingDeletion = nil
            }
            Button("취소", role: .cancel) {
                memoryPendingDeletion = nil
            }
        } message: { memory in
            Text("‘\(memory.title)’ 메모리를 삭제하면 복구할 수 없어요.")
        }
        .confirmationDialog(
            "모든 사용자 메모리를 삭제할까요?",
            isPresented: $isShowingClearAllMemoriesConfirmation
        ) {
            Button("전체 삭제", role: .destructive) {
                viewModel.deleteAllUserMemories()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장된 사용자 메모리 전체가 삭제되며 복구할 수 없어요.")
        }
        .sheet(item: $memoryEditor) { editor in
            UserMemoryEditorView(memory: editor.memory) { title, body, category in
                if let memory = editor.memory {
                    viewModel.updateUserMemory(
                        id: memory.id,
                        title: title,
                        body: body,
                        category: category
                    )
                } else {
                    viewModel.addUserMemory(title: title, body: body, category: category)
                }
            }
        }
        .onChange(of: viewModel.lastAnswer) {
            hasSavedLatestAnswer = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                isAnswerIslandExpanded = true
            }
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
                    Label("메모리", systemImage: "bookmark")
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
                    dashboardEntrance(deviceOverview, stage: 1)

                    if let activity = lumiActivity {
                        dashboardEntrance(activityIsland(activity), stage: 2)
                    } else if let answer = viewModel.lastAnswer {
                        dashboardEntrance(answerIsland(answer), stage: 2)
                    }

                    dashboardEntrance(aiControlCard, stage: 3)

                    dashboardEntrance(recentMemoriesSection, stage: 4)
                }
                .padding(.horizontal, SeedSpacing.globalGutter)
                .padding(.top, SeedSpacing.x3)
                .padding(.bottom, SeedSpacing.screenBottom)
            }
            .scrollIndicators(.hidden)
            .background(SeedColor.layerBasement)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear(perform: playDashboardEntranceIfNeeded)
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                dashboardEntranceStage = 4
            }
        }
    }

    private func dashboardEntrance<Content: View>(_ content: Content, stage: Int) -> some View {
        let isVisible = reduceMotion || dashboardEntranceStage >= stage

        return content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.985)
            .offset(y: isVisible ? 0 : SeedSpacing.x4)
            .animation(
                reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9),
                value: dashboardEntranceStage
            )
    }

    private func playDashboardEntranceIfNeeded() {
        guard !hasPlayedDashboardEntrance else { return }

        hasPlayedDashboardEntrance = true

        guard !reduceMotion else {
            dashboardEntranceStage = 4
            return
        }

        let stages: [(stage: Int, delay: TimeInterval)] = [
            (1, 0.04),
            (2, 0.14),
            (3, 0.24),
            (4, 0.34)
        ]

        for item in stages {
            DispatchQueue.main.asyncAfter(deadline: .now() + item.delay) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                    dashboardEntranceStage = item.stage
                }
            }
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

                VStack(alignment: .leading, spacing: SeedSpacing.x0_5) {
                    Text("시작 \(conversation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("최근 \(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption2)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ray-Ban Meta")
                    .font(.system(size: homeTitleSize, weight: .bold, design: .default))
                    .foregroundStyle(SeedColor.fgNeutral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                settingsMenu
            }
            .padding(.top, SeedSpacing.x2)

            connectionStatus
                .padding(.top, SeedSpacing.x4)

            Image("RayBanMetaGlasses")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 220)
                .shadow(color: .black.opacity(0.2), radius: 15, x: 3, y: 5)
                .offset(y: -14)
                .frame(height: 116)
                .clipped()
                .padding(.top, SeedSpacing.x7)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

        }
        .frame(maxWidth: .infinity)
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

            Text(deviceConnectionTitle)
                .font(.title3.weight(.regular))
                .foregroundStyle(SeedColor.fgMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ray-Ban Meta")
        .accessibilityValue(deviceConnectionTitle)
    }

    private var aiControlCard: some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x5) {
            Text("AI 제어")
                .font(.title3.weight(.bold))
                .foregroundStyle(SeedColor.fgNeutral)

            if viewModel.isGlassesAvailable {
                HStack(spacing: 0) {
                    deviceActionButton(
                        symbol: "camera",
                        label: sceneButtonTitle,
                        hint: "안경 카메라로 사진 한 장을 촬영해 장면을 설명합니다.",
                        isLoading: viewModel.isCapturingScene,
                        isDisabled: viewModel.isBusy || viewModel.isRegistering,
                        action: performSceneAction
                    )
                    .frame(maxWidth: .infinity)

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
                    .frame(maxWidth: .infinity)

                    deviceActionButton(
                        symbol: "bubble.left.and.bubble.right",
                        label: "대화 보기",
                        hint: "현재 대화 세션과 이전 대화를 확인합니다.",
                        isLoading: false,
                        isDisabled: false,
                        action: { selectedTab = .conversations }
                    )
                    .frame(maxWidth: .infinity)

                    deviceActionButton(
                        symbol: "bookmark",
                        label: "사용자 메모리 보기",
                        hint: "Lumi가 명시적으로 저장한 사용자 메모리를 확인합니다.",
                        isLoading: false,
                        isDisabled: false,
                        action: { selectedTab = .memories }
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
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
                .accessibilityHint("Meta AI 앱에서 Lumi와 안경의 연결을 시작합니다.")
            }
        }
        .padding(SeedSpacing.x5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedColor.layerDefault, in: RoundedRectangle(cornerRadius: SeedRadius.r5, style: .continuous))
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
                                : (isPrimary || isCritical ? SeedColor.onBrand : SeedColor.fgNeutral)
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

    private func answerIsland(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SeedSpacing.x2) {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        isAnswerIslandExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: SeedSpacing.x2) {
                        Image(systemName: viewModel.isSpeaking ? "waveform" : "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .foregroundStyle(SeedColor.fgInverted)

                        Text("Lumi")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SeedColor.fgInverted)

                        if !isAnswerIslandExpanded {
                            Text("새 답변")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(SeedColor.fgInverted.opacity(0.62))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAnswerIslandExpanded ? "Lumi 답변 접기" : "Lumi 답변 펼치기")

                Spacer(minLength: SeedSpacing.x2)

                Button {
                    selectedTab = .conversations
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedColor.fgInverted)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("전체 대화 보기")
            }

            if isAnswerIslandExpanded {
                VStack(alignment: .leading, spacing: SeedSpacing.x3) {
                    if let transcript = viewModel.lastTranscript, !transcript.isEmpty {
                        Text("“\(transcript)”")
                            .font(.caption)
                            .foregroundStyle(SeedColor.fgInverted.opacity(0.58))
                            .lineLimit(1)
                    }

                    Text(answer)
                        .font(.body.weight(.medium))
                        .foregroundStyle(SeedColor.fgInverted)
                        .lineSpacing(3)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("방금 답했어요")
                            .font(.caption)
                            .foregroundStyle(SeedColor.fgInverted.opacity(0.58))

                        Spacer()

                        Button {
                            viewModel.saveLatestAnswerToUserMemory()
                            withAnimation(.easeOut(duration: 0.2)) {
                                hasSavedLatestAnswer = true
                            }
                        } label: {
                            Image(systemName: hasSavedLatestAnswer ? "checkmark" : "bookmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(SeedColor.fgInverted)
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(hasSavedLatestAnswer)
                        .accessibilityLabel(hasSavedLatestAnswer ? "사용자 메모리에 저장됨" : "답변을 사용자 메모리에 저장")
                    }
                }
                .padding(.top, SeedSpacing.x3)
            }
        }
        .padding(SeedSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedColor.neutralSolid, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isAnswerIslandExpanded)
    }

    private func activityIsland(_ activity: LumiActivity) -> some View {
        HStack(spacing: SeedSpacing.x3) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SeedColor.fgInverted.opacity(0.82))
                .frame(width: 20, height: 20)

            LumiActivityIndicator(activity: activity)

            Spacer(minLength: SeedSpacing.x2)

            HStack(spacing: SeedSpacing.x1) {
                Circle()
                    .fill(SeedColor.fgInverted)
                    .frame(width: 5, height: 5)
                Circle()
                    .fill(SeedColor.fgInverted.opacity(0.42))
                    .frame(width: 5, height: 5)
                Circle()
                    .fill(SeedColor.fgInverted.opacity(0.2))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, SeedSpacing.x5)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(SeedColor.neutralSolid, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.accessibilityLabel)
    }

    private var recentMemoriesSection: some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x3) {
            HStack(alignment: .bottom) {
                sectionHeader(title: "사용자 메모리", detail: "직접 저장한 중요한 내용")
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
                    title: "저장한 사용자 메모리가 없어요",
                    description: "답변을 저장하거나 “이건 기억해줘”처럼 명확히 요청하면 여기에 모아드려요.",
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

                memoryCategoryFilter
                    .padding(.bottom, SeedSpacing.x2)
                    .background(SeedColor.layerDefault)

                memoryDateFilter
                    .padding(.bottom, SeedSpacing.x3)
                    .background(SeedColor.layerDefault)

                if viewModel.selectedMemoryDateFilter == .custom {
                    memoryDatePicker
                        .padding(.horizontal, SeedSpacing.globalGutter)
                        .padding(.bottom, SeedSpacing.x3)
                        .background(SeedColor.layerDefault)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SeedSpacing.x4) {
                        SeedCallout(
                            symbol: "iphone.gen3",
                            title: "이 iPhone에만 저장돼요",
                            description: "사용자 메모리는 기본적으로 이 iPhone 안에 보관돼요.",
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
            .navigationTitle("사용자 메모리")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        memoryEditor = UserMemoryEditor()
                    } label: {
                        Label("메모리 추가", systemImage: "plus")
                    }
                    .accessibilityHint("직접 입력할 사용자 메모리를 추가합니다.")

                    settingsMenu
                }
            }
        }
    }

    private var memorySearchField: some View {
        HStack(spacing: SeedSpacing.x2_5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SeedColor.fgSubtle)

            TextField("사용자 메모리 검색", text: $viewModel.memoSearchQuery)
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

    private var memoryCategoryFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SeedSpacing.x2) {
                memoryCategoryFilterButton(nil)

                ForEach(UserMemoryCategory.allCases) { category in
                    memoryCategoryFilterButton(category)
                }
            }
            .padding(.horizontal, SeedSpacing.globalGutter)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("사용자 메모리 카테고리 필터")
    }

    private func memoryCategoryFilterButton(_ category: UserMemoryCategory?) -> some View {
        let isSelected = viewModel.selectedMemoryCategory == category
        let title = category?.title ?? "전체"

        return Button {
            viewModel.selectedMemoryCategory = category
        } label: {
            HStack(spacing: SeedSpacing.x1) {
                if let category {
                    Image(systemName: category.symbol)
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? SeedColor.onBrand : SeedColor.fgMuted)
            .padding(.horizontal, SeedSpacing.x3)
            .frame(minHeight: 36)
            .background(
                isSelected ? SeedColor.brand : SeedColor.layerFill,
                in: Capsule()
            )
            .overlay {
                if !isSelected {
                    Capsule()
                        .stroke(SeedColor.strokeSubtle, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) 메모리 보기")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var memoryDateFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SeedSpacing.x2) {
                ForEach(
                    [
                        UserMemoryDateFilter.all,
                        .today,
                        .yesterday,
                        .thisWeek,
                        .custom
                    ],
                    id: \.self
                ) { filter in
                    memoryDateFilterButton(filter)
                }
            }
            .padding(.horizontal, SeedSpacing.globalGutter)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("사용자 메모리 날짜 필터")
    }

    private func memoryDateFilterButton(_ filter: UserMemoryDateFilter) -> some View {
        let isSelected = viewModel.selectedMemoryDateFilter == filter

        return Button {
            viewModel.selectedMemoryDateFilter = filter
        } label: {
            HStack(spacing: SeedSpacing.x1) {
                if filter == .custom {
                    Image(systemName: "calendar")
                }
                Text(filter.title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? SeedColor.onBrand : SeedColor.fgMuted)
            .padding(.horizontal, SeedSpacing.x3)
            .frame(minHeight: 36)
            .background(
                isSelected ? SeedColor.brand : SeedColor.layerFill,
                in: Capsule()
            )
            .overlay {
                if !isSelected {
                    Capsule()
                        .stroke(SeedColor.strokeSubtle, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title) 메모리 보기")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var memoryDatePicker: some View {
        HStack(spacing: SeedSpacing.x2) {
            Label("기록 날짜", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SeedColor.fgMuted)

            Spacer()

            DatePicker(
                "기록 날짜",
                selection: $viewModel.selectedMemoryDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .labelsHidden()
        }
        .padding(.horizontal, SeedSpacing.x3)
        .frame(minHeight: 44)
        .background(SeedColor.layerFill, in: RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous))
    }

    @ViewBuilder
    private var memoryContent: some View {
        if viewModel.memos.isEmpty {
            VStack(spacing: SeedSpacing.x4) {
                emptyMemoryState(
                    symbol: "bookmark",
                    title: "저장한 사용자 메모리가 없어요",
                    detail: "음성 질문에서 “이건 기억해줘”라고 말하거나 직접 입력해보세요."
                )

                Button("메모리 직접 추가") {
                    memoryEditor = UserMemoryEditor()
                }
                .buttonStyle(SeedActionButtonStyle(variant: .neutralWeak, size: .medium))
            }
        } else if viewModel.filteredMemos.isEmpty {
            VStack(spacing: SeedSpacing.x4) {
                emptyMemoryState(
                    symbol: "magnifyingglass",
                    title: memoryEmptyFilterTitle,
                    detail: memoryEmptyFilterDetail
                )

                Button("필터 지우기") {
                    viewModel.clearMemoryFilters()
                }
                .buttonStyle(SeedActionButtonStyle(variant: .neutralWeak, size: .medium))
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("사용자 메모리 \(viewModel.filteredMemos.count)개")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SeedColor.fgMuted)
                    Spacer()
                    Button("전체 삭제", role: .destructive) {
                        isShowingClearAllMemoriesConfirmation = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SeedColor.fgMuted)
                }
                .padding(.horizontal, SeedSpacing.x4)
                .padding(.vertical, SeedSpacing.x3)

                Divider()

                ForEach(Array(viewModel.filteredMemos.enumerated()), id: \.element.id) { index, memo in
                    memoryRow(memo, showsManagement: true)

                    if index < viewModel.filteredMemos.count - 1 {
                        Divider()
                            .padding(.leading, SeedSpacing.x12)
                    }
                }
            }
            .seedSurface(radius: SeedRadius.r4)
        }
    }

    private var memoryEmptyFilterTitle: String {
        if !viewModel.memoSearchQuery.isEmpty { return "검색 결과가 없어요" }
        if viewModel.hasActiveMemoryDateFilter { return "선택한 날짜에 메모리가 없어요" }
        return "선택한 카테고리에 메모리가 없어요"
    }

    private var memoryEmptyFilterDetail: String {
        if !viewModel.memoSearchQuery.isEmpty { return "다른 검색어로 다시 찾아보세요." }
        if viewModel.hasActiveMemoryDateFilter { return "다른 날짜를 선택하거나 날짜 필터를 지워보세요." }
        return "다른 카테고리를 선택하거나 직접 추가해보세요."
    }

    private func memoryRow(_ memo: VoiceMemo, showsManagement: Bool = false) -> some View {
        HStack(alignment: .top, spacing: SeedSpacing.x3) {
            Image(systemName: memo.category.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedColor.brand)
                .frame(width: 36, height: 36)
                .background(SeedColor.brandWeak, in: RoundedRectangle(cornerRadius: SeedRadius.r2_5, style: .continuous))

            VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                Text(memo.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SeedColor.fgNeutral)

                Text(memo.category.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SeedColor.brand)
                    .padding(.horizontal, SeedSpacing.x1_5)
                    .padding(.vertical, SeedSpacing.x0_5)
                    .background(
                        SeedColor.brandWeak,
                        in: Capsule(style: .continuous)
                    )

                Text(memo.body)
                    .font(.subheadline)
                    .foregroundStyle(SeedColor.fgMuted)
                    .lineLimit(3)

                if let photoFilename = memo.photoFilename {
                    UserMemoryPhotoThumbnail(filename: photoFilename)
                        .padding(.top, SeedSpacing.x1)
                }

                if let location = memo.location {
                    VStack(alignment: .leading, spacing: SeedSpacing.x1) {
                        Label(location.displayName, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(SeedColor.fgMuted)
                            .lineLimit(2)

                        if let mapURL = location.mapURL {
                            Link(destination: mapURL) {
                                Label("지도에서 열기", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(SeedColor.brand)
                        }
                    }
                    .padding(.top, SeedSpacing.x1)
                }

                Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(SeedColor.fgSubtle)
            }

            Spacer(minLength: 0)

            if showsManagement {
                Button {
                    memoryEditor = UserMemoryEditor(memory: memo)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedColor.fgSubtle)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(memo.title) 편집")

                Button {
                    memoryPendingDeletion = memo
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedColor.fgSubtle)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(memo.title) 삭제")
            }
        }
        .padding(.horizontal, SeedSpacing.x3)
        .padding(.vertical, SeedSpacing.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 21, weight: .semibold))
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

    private var lumiActivity: LumiActivity? {
        if viewModel.isRecording { return .listening }
        if viewModel.isStartingVoice { return .preparingVoice }
        if viewModel.isCapturingScene { return .capturingScene }
        if viewModel.isProcessing { return .processing }
        if viewModel.isSpeaking { return .speaking }
        if viewModel.isRegistering { return .connecting }
        return nil
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

private struct UserMemoryEditor: Identifiable {
    let id = UUID()
    let memory: VoiceMemo?

    init(memory: VoiceMemo? = nil) {
        self.memory = memory
    }
}

private struct UserMemoryEditorView: View {
    let memory: VoiceMemo?
    let onSave: (String, String, UserMemoryCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var memoryBody: String
    @State private var category: UserMemoryCategory

    init(
        memory: VoiceMemo?,
        onSave: @escaping (String, String, UserMemoryCategory) -> Void
    ) {
        self.memory = memory
        self.onSave = onSave
        _title = State(initialValue: memory?.title ?? "")
        _memoryBody = State(initialValue: memory?.body ?? "")
        _category = State(initialValue: memory?.category ?? .general)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !memoryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var bodyView: some View {
        NavigationStack {
            Form {
                Section("메모리 내용") {
                    TextField("제목", text: $title)

                    TextEditor(text: $memoryBody)
                        .frame(minHeight: 128)
                        .accessibilityLabel("메모리 내용")
                }

                Section("카테고리") {
                    Picker("카테고리", selection: $category) {
                        ForEach(UserMemoryCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol)
                                .tag(category)
                        }
                    }

                    if category == .parking {
                        Label("주차 기억은 최신 항목 하나만 보관돼요.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if category == .place {
                        Label("현재 장소를 저장할 때 사진과 위치가 함께 추가돼요.", systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(memory == nil ? "메모리 추가" : "메모리 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(title, memoryBody, category)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    var body: some View {
        bodyView
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
                        sessionTimeline(conversation)

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
                if let photoFilename = message.photoFilename {
                    ConversationPhotoThumbnail(filename: photoFilename)
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? SeedColor.onBrand : SeedColor.fgNeutral)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SeedSpacing.x3)
                    .padding(.vertical, SeedSpacing.x2_5)
                    .background(
                        message.role == .user ? SeedColor.brand : SeedColor.layerFill,
                        in: RoundedRectangle(cornerRadius: SeedRadius.r4, style: .continuous)
                    )

                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
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

    private func sessionTimeline(_ conversation: ConversationSession) -> some View {
        VStack(alignment: .leading, spacing: SeedSpacing.x1) {
            Text("세션 정보")
                .font(.caption.weight(.bold))
                .foregroundStyle(SeedColor.fgMuted)

            Text("시작 \(conversation.createdAt.formatted(date: .abbreviated, time: .shortened)) · 최근 갱신 \(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(SeedColor.fgSubtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SeedSpacing.x3)
        .padding(.vertical, SeedSpacing.x2_5)
        .background(SeedColor.layerFill, in: RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func scrollToLatestMessage(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}

private struct ConversationPhotoThumbnail: View {
    let filename: String

    var body: some View {
        Group {
            if let image = ConversationPhotoStore.image(for: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ContentUnavailableView(
                    "사진을 불러올 수 없어요",
                    systemImage: "photo"
                )
                .font(.caption)
                .foregroundStyle(SeedColor.fgSubtle)
            }
        }
        .frame(width: 228, height: 168)
        .background(SeedColor.layerFill)
        .clipShape(RoundedRectangle(cornerRadius: SeedRadius.r4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SeedRadius.r4, style: .continuous)
                .stroke(SeedColor.strokeSubtle, lineWidth: 0.5)
        }
        .accessibilityLabel("안경으로 촬영한 장면 사진")
    }
}

private struct UserMemoryPhotoThumbnail: View {
    let filename: String

    var body: some View {
        Group {
            if let image = UserMemoryPhotoStore.image(for: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ContentUnavailableView(
                    "장소 사진을 불러올 수 없어요",
                    systemImage: "photo"
                )
                .font(.caption)
                .foregroundStyle(SeedColor.fgSubtle)
            }
        }
        .frame(width: 156, height: 104)
        .background(SeedColor.layerFill)
        .clipShape(RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SeedRadius.r3, style: .continuous)
                .stroke(SeedColor.strokeSubtle, lineWidth: 0.5)
        }
        .accessibilityLabel("저장한 장소 사진")
    }
}

private enum LumiActivity: Hashable {
    case preparingVoice
    case listening
    case processing
    case capturingScene
    case speaking
    case connecting

    var accessibilityLabel: String {
        switch self {
        case .preparingVoice:
            return "Lumi가 안경 마이크를 준비하고 있습니다"
        case .listening:
            return "Lumi가 듣고 있습니다"
        case .processing:
            return "Lumi가 답변을 준비하고 있습니다"
        case .capturingScene:
            return "Lumi가 안경 카메라로 장면을 분석하고 있습니다"
        case .speaking:
            return "Lumi가 안경 스피커로 답변을 들려주고 있습니다"
        case .connecting:
            return "Lumi가 안경 연결을 준비하고 있습니다"
        }
    }
}

private struct LumiActivityIndicator: View {
    let activity: LumiActivity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Group {
            switch activity {
            case .listening, .speaking:
                waveform
            case .processing:
                thinkingDots
            case .capturingScene:
                scanningViewfinder
            case .preparingVoice:
                pulsingSymbol("mic.fill")
            case .connecting:
                pulsingSymbol("link")
            }
        }
        .frame(width: 72, height: 32, alignment: .leading)
        .onAppear {
            startAnimation()
        }
        .onChange(of: activity) {
            isAnimating = false
            startAnimation()
        }
    }

    private var waveform: some View {
        HStack(spacing: SeedSpacing.x1) {
            ForEach(Array([12, 22, 30, 18, 10].enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(SeedColor.fgInverted)
                    .frame(width: 4, height: CGFloat(height))
                    .scaleEffect(
                        y: isAnimating ? (index.isMultiple(of: 2) ? 0.52 : 1) : 0.4,
                        anchor: .center
                    )
                    .opacity(isAnimating ? 1 : 0.5)
                    .animation(
                        repeatingAnimation(delay: Double(index) * 0.09),
                        value: isAnimating
                    )
            }
        }
    }

    private var thinkingDots: some View {
        HStack(spacing: SeedSpacing.x2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(SeedColor.fgInverted)
                    .frame(width: 7, height: 7)
                    .offset(y: isAnimating ? -5 : 3)
                    .opacity(isAnimating ? 1 : 0.35)
                    .animation(
                        repeatingAnimation(delay: Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
    }

    private var scanningViewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SeedColor.fgInverted.opacity(0.68), lineWidth: 1.5)
                .frame(width: 28, height: 28)
                .scaleEffect(isAnimating ? 1 : 0.74)
                .opacity(isAnimating ? 0.95 : 0.4)
                .animation(repeatingAnimation(), value: isAnimating)

            Circle()
                .fill(SeedColor.fgInverted)
                .frame(width: 7, height: 7)
                .scaleEffect(isAnimating ? 1.2 : 0.5)
                .animation(repeatingAnimation(delay: 0.16), value: isAnimating)
        }
    }

    private func pulsingSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(SeedColor.fgInverted)
            .scaleEffect(isAnimating ? 1 : 0.72)
            .opacity(isAnimating ? 1 : 0.48)
            .animation(repeatingAnimation(), value: isAnimating)
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        DispatchQueue.main.async {
            isAnimating = true
        }
    }

    private func repeatingAnimation(delay: Double = 0) -> Animation {
        .easeInOut(duration: 0.72)
            .repeatForever(autoreverses: true)
            .delay(delay)
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
