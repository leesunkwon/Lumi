//
//  ContentView.swift
//  MetaGemini
//
//  Created by sunkwon on 8/29/26.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: LumiViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    connectionCard
                    conversationCard
                    sceneCard
                    memorySection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lumi")
            .navigationBarTitleDisplayMode(.large)
            .alert("Lumi", isPresented: $viewModel.isShowingError) {
                Button("확인", role: .cancel) {
                    viewModel.dismissError()
                }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("보고 묻고, 듣는 개인 비서")
                .font(.title3.weight(.semibold))
            Text("안경으로 듣고 보고, 답은 귀로 받아보세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "eyeglasses")
                    .font(.title2)
                    .foregroundStyle(viewModel.isGlassesAvailable ? .green : .secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.glassesStatusTitle)
                        .font(.headline)
                    Text(viewModel.glassesStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isRegistering {
                    ProgressView()
                }
            }

            Button(viewModel.connectionButtonTitle) {
                viewModel.connectGlasses()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRegistering || viewModel.isGlassesAvailable)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var conversationCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(viewModel.isRecording ? "듣고 있어요" : "무엇을 도와드릴까요?")
                    .font(.headline)
                Text(viewModel.isRecording ? "질문이 끝나면 다시 눌러 전송하세요." : "버튼을 눌러 안경에 대고 말하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.toggleVoiceQuestion()
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 112, height: 112)
                        .shadow(color: (viewModel.isRecording ? Color.red : Color.accentColor).opacity(0.28), radius: 14, y: 8)

                    if viewModel.isStartingVoice || viewModel.isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isStartingVoice || viewModel.isProcessing || viewModel.isCapturingScene)
            .accessibilityLabel(viewModel.isRecording ? "질문 전송" : "음성 질문 시작")

            if let answer = viewModel.lastAnswer {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Lumi의 답변", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(answer)
                        .font(.body)

                    Button("답변을 메모로 저장", systemImage: "bookmark") {
                        viewModel.saveLatestAnswerAsMemo()
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var sceneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("장면 보기", systemImage: "camera.viewfinder")
                .font(.headline)

            Text("안경 카메라로 사진 한 장을 찍어 눈앞의 장면을 설명합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                viewModel.describeScene()
            } label: {
                HStack {
                    if viewModel.isCapturingScene {
                        ProgressView()
                    } else {
                        Image(systemName: "eye")
                    }
                    Text(viewModel.isCapturingScene ? "장면을 살펴보는 중" : "지금 보는 장면 설명")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isGlassesAvailable || viewModel.isBusy)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기억한 메모")
                .font(.headline)

            TextField("메모 검색", text: $viewModel.memoSearchQuery)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredMemos.isEmpty {
                ContentUnavailableView(
                    "저장한 메모가 없어요",
                    systemImage: "bookmark",
                    description: Text("“기억해줘”라고 말하거나 답변을 저장해보세요.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredMemos) { memo in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(memo.title)
                                .font(.subheadline.weight(.semibold))
                            Text(memo.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ContentView(viewModel: .preview)
}
