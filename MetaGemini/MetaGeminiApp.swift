//
//  MetaGeminiApp.swift
//  MetaGemini
//
//  Created by sunkwon on 8/29/26.
//

import MWDATCore
import SwiftUI

@main
struct MetaGeminiApp: App {
    @State private var viewModel: LumiViewModel

    init() {
        let configurationError: String?

        do {
            try Wearables.configure()
            configurationError = nil
        } catch {
            configurationError = error.localizedDescription
        }

        _viewModel = State(
            initialValue: LumiViewModel(
                wearables: Wearables.shared,
                configurationError: configurationError
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.handleMetaCallback(url)
                }
        }
    }
}
