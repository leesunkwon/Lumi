//
//  LumiPreferences.swift
//  MetaGemini
//

import Foundation

enum LumiPreferences {
    static let confirmBeforeActionKey = "lumi.confirm-before-action"

    static var confirmsActionsBeforeExecution: Bool {
        guard UserDefaults.standard.object(forKey: confirmBeforeActionKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: confirmBeforeActionKey)
    }
}
