//
//  DownloadManagerBackingStore.swift
//
//  Created by Gabriel Nica on 06/08/2019.
//  Copyright © 2019 Shaped by Iris. All rights reserved.

import Foundation

public class DownloadManagerBackingStore {
    private let downloadsKey = "DownloadManagerBackingStore"

    private var inMemoryDownloadItems: [URL: DownloadItem] = [:]
    private let userDefaults = UserDefaults.standard

    var downloads: [URL] {
        loadDownloads()
        return inMemoryDownloadItems.keys.map { $0 }
    }

    var downloadItems: [DownloadItem] {
        loadDownloads()
        return inMemoryDownloadItems.values.map { $0 }
    }

    // MARK: - Load

    private func loadDictionary() -> [URL: DownloadItem]? {
        guard let data = userDefaults.object(forKey: downloadsKey) as? Data else {
            return nil
        }
        let decoder = JSONDecoder()

        return try? decoder.decode([URL: DownloadItem].self, from: data)
    }

    private func saveDictionary() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(inMemoryDownloadItems) {
            userDefaults.set(encoded, forKey: downloadsKey)
        }
    }

    public func loadDownloads() {
        if let items = loadDictionary() {
            inMemoryDownloadItems.merge(items) { first, _ in first }
        }
    }

    public func downloadItem(withURL url: URL) -> DownloadItem? {
        if let downloadItem = inMemoryDownloadItems[url] {
            return downloadItem
        } else if let downloadItem = loadDownloadItemFromStorage(withURL: url) {
            inMemoryDownloadItems[downloadItem.remoteURL] = downloadItem
            return downloadItem
        }

        return nil
    }

    private func loadDownloadItemFromStorage(withURL url: URL) -> DownloadItem? {
        guard let encodedData = loadDictionary() else {
            return nil
        }

        let downloadItem = encodedData[url]
        return downloadItem
    }

    // MARK: - Save

    func saveDownloadItem(_ downloadItem: DownloadItem) {
        inMemoryDownloadItems[downloadItem.remoteURL] = downloadItem

        saveDictionary()
        userDefaults.synchronize()
    }

    // MARK: - Delete

    func deleteDownloadItem(_ downloadItem: DownloadItem) {
        inMemoryDownloadItems[downloadItem.remoteURL] = nil
        userDefaults.removeObject(forKey: downloadsKey)
        saveDictionary()
        userDefaults.synchronize()
    }

    func deleteDownload(url: URL) {
        inMemoryDownloadItems.removeValue(forKey: url)
        userDefaults.removeObject(forKey: downloadsKey)
        saveDictionary()
        userDefaults.synchronize()
    }

    func deleteAll() {
        inMemoryDownloadItems.removeAll()
        userDefaults.removeObject(forKey: downloadsKey)
        saveDictionary()
        userDefaults.synchronize()
    }
}
