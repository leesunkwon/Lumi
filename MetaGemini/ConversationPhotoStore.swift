//
//  ConversationPhotoStore.swift
//  MetaGemini
//

import Foundation
import UIKit

enum ConversationPhotoStore {
    private static let directoryName = "ConversationPhotos"

    static func save(_ imageData: Data) throws -> String {
        let filename = "\(UUID().uuidString).jpg"
        let destination = try directoryURL().appendingPathComponent(filename)
        try imageData.write(to: destination, options: .atomic)
        return filename
    }

    static func image(for filename: String) -> UIImage? {
        guard let url = try? directoryURL().appendingPathComponent(filename) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    private static func directoryURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
