//
//  LumiPreferences.swift
//  MetaGemini
//

import Foundation

enum LumiPreferences {
    static let confirmBeforeActionKey = "lumi.confirm-before-action"
    static let experimentalKeyboardInputKey = "lumi.experimental-keyboard-input"

    static var confirmsActionsBeforeExecution: Bool {
        guard UserDefaults.standard.object(forKey: confirmBeforeActionKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: confirmBeforeActionKey)
    }
}
