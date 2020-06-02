//
//  DownloadManager.swift
//
//  Created by Gabriel Nica on 06/08/2019.
//  Copyright © 2019 Shaped by Iris. All rights reserved.
//
//  swiftlint:disable line_length

import Foundation
import UserNotifications

public typealias DownloadCompletionBlock = (_ error: Error?, _ fileUrl: URL?) -> Void
public typealias DownloadProgressBlock = (_ progress: Float) -> Void
public typealias BackgroundDownloadCompletionHandler = () -> Void

public extension Notification.Name {
    static let downloadAddedToQueue = Notification.Name("com.shapedbyiris.downloadAddedToQueue")
    static let downloadRemovedFromQueue = Notification.Name("com.shapedbyiris.downloadRemovedFromQueue")
    static let downloadFinished = Notification.Name("com.shapedbyiris.downloadFinished")
    static let downloadProgress = Notification.Name("com.shapedbyiris.downloadProgress")
    static let downloadFailed = Notification.Name("com.shapedbyiris.downloadFailed")
}

public class DownloadItem: Codable {
    let remoteURL: URL
    let destinationURL: URL
    fileprivate(set) var retryCount: Int = 0

    private enum CodingKeys: CodingKey {
        case remoteURL
        case destinationURL
        case retryCount
    }

    var completionBlock: DownloadCompletionBlock?
    var progressBlock: DownloadProgressBlock?

    init(remoteURL: URL,
         destinationURL: URL,
         progressBlock: DownloadProgressBlock?,
         completionBlock: DownloadCompletionBlock?) {
        self.remoteURL = remoteURL
        self.completionBlock = completionBlock
        self.progressBlock = progressBlock
        self.destinationURL = destinationURL
    }
}

public struct DownloadManagerConfig {
    public var maximumRetries = 3
    public var exponentialBackoffMultiplier = 10
    public var usesNotificationCenter = false
    public var showsLocalNotifications = false
    public var logVerbosity: LogVerbosity = .none
}

public final class DownloadManager: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    public static let shared = DownloadManager()

    public var configuration = DownloadManagerConfig()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Bundle.main.bundleIdentifier!)
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        #if !os(macOS)
        config.sessionSendsLaunchEvents = true
        #endif

        let urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        return urlSession
    }()

    private var backingStore = DownloadManagerBackingStore()

    public var downloads: [URL] {
        return backingStore.downloads
    }

    public var backgroundDownloadCompletionHandler: BackgroundDownloadCompletionHandler?
    private var localNotificationText: String?

    private override init() {
        super.init()
        backingStore.loadDownloads()

        for item in backingStore.downloadItems {
            if rescheduleDownload(resumeData: nil, downloadItem: item) == false {
                backingStore.deleteDownloadItem(item)
            }
        }
    }

    public func addDownload(url: URL,
                            destinationURL: URL,
                            onProgress progressBlock: DownloadProgressBlock? = nil,
                            onCompletion completionBlock: @escaping DownloadCompletionBlock) {
        guard backingStore.downloadItem(withURL: url) == nil else {
            os_log(verbosity: configuration.logVerbosity, type: .debug, format: "%@ Already in progress", args: url.lastPathComponent)
            return
        }

        let urlRequest = URLRequest(url: url)
        let downloadTask = session.downloadTask(with: urlRequest)

        let downloadItem = DownloadItem(remoteURL: url, destinationURL: destinationURL,
                                        progressBlock: progressBlock, completionBlock: completionBlock)

        backingStore.saveDownloadItem(downloadItem)

        downloadTask.resume()

        os_log(verbosity: configuration.logVerbosity, type: .debug, format: "Added %@ to download queue", args: url.lastPathComponent)
        if configuration.usesNotificationCenter {
            NotificationCenter.default.post(name: .downloadAddedToQueue, object: url)
        }
    }

    public func cancelAllDownloads() {
        session.getTasksWithCompletionHandler { _, _, downloadTasks in
            for task in downloadTasks {
                task.cancel()
            }
        }

        if configuration.usesNotificationCenter {
            for item in backingStore.downloadItems {
                NotificationCenter.default.post(name: .downloadRemovedFromQueue, object: item.remoteURL, userInfo: nil)
            }
        }

        backingStore.deleteAll()
    }

    public func cancelDownload(withURL url: URL) {
        session.getTasksWithCompletionHandler { _, _, downloadTasks in
            for task in downloadTasks {
                if let taskUrl = task.originalRequest?.url, url == taskUrl {
                    task.cancel()

                    self.backingStore.deleteDownload(url: url)
                    if self.configuration.usesNotificationCenter {
                        NotificationCenter.default.post(name: .downloadRemovedFromQueue, object: url, userInfo: nil)
                    }
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let url = downloadTask.originalRequest?.url, let download = backingStore.downloadItem(withURL: url), let response = downloadTask.response as? HTTPURLResponse else {
            return
        }

        let statusCode = response.statusCode

        guard statusCode < 400 else {
            if rescheduleDownload(resumeData: nil, downloadItem: download) == false {
                OperationQueue.main.addOperation {
                    let error = NSError(domain: "HttpError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: statusCode)])

                    os_log(verbosity: self.configuration.logVerbosity, type: .error, format: "Download error: %@", args: error.localizedDescription)
                    download.completionBlock?(error, nil)
                }

                backingStore.deleteDownloadItem(download)
            }
            return
        }

        do {
            let fileName = downloadTask.response?.suggestedFilename ?? download.remoteURL.lastPathComponent
            let destinationURL = download.destinationURL
            let url = try FileManager.default.moveFile(at: location, to: destinationURL, fileName: fileName, overwrite: true)

            os_log(verbosity: configuration.logVerbosity, type: .debug, format: "Download complete: %@", args: download.remoteURL.lastPathComponent)
            DispatchQueue.main.async {
                #if DEBUG
                self.showLocalNotification(defaultText: "Download complete: \(download.remoteURL.lastPathComponent)")
                #endif
                download.completionBlock?(nil, url)
                self.backingStore.deleteDownloadItem(download)
                if self.configuration.usesNotificationCenter {
                    NotificationCenter.default.post(name: .downloadRemovedFromQueue, object: url)
                    NotificationCenter.default.post(name: .downloadFinished, object: (download.remoteURL, url))
                }
            }

        } catch {
            os_log(verbosity: configuration.logVerbosity, type: .debug, format: "Download complete but unable to be moved: %@", args: download.remoteURL.lastPathComponent)
            download.completionBlock?(error, nil)
            backingStore.deleteDownloadItem(download)
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else {
            debugPrint("Could not calculate progress as totalBytesExpectedToWrite is 0")
            return
        }

        guard let url = downloadTask.originalRequest?.url, let downloadItem = backingStore.downloadItem(withURL: url) else {
            return
        }

        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        os_log(verbosity: configuration.logVerbosity, type: .debug, format: "%@ progress: %.0f", args: downloadItem.remoteURL.lastPathComponent, progress)

        if let progressBlock = downloadItem.progressBlock {
            DispatchQueue.main.async {
                progressBlock(progress)
            }
        }

        if configuration.usesNotificationCenter {
            if downloadTask.error == nil {
                NotificationCenter.default.post(name: .downloadProgress, object: (url, progress))
            } else {
                NotificationCenter.default.post(name: .downloadFailed, object: url)
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask, let url = downloadTask.originalRequest?.url, let download = backingStore.downloadItem(withURL: url) else {
            return
        }
        if let error = error {
            let userInfo = (error as NSError).userInfo
            guard let resumeData = userInfo[NSURLSessionDownloadTaskResumeData] as? Data, rescheduleDownload(resumeData: resumeData, downloadItem: download) else {
                DispatchQueue.main.async {
                    download.completionBlock?(error, nil)
                }

                backingStore.deleteDownload(url: url)

                return
            }

            debugPrint("Retry \(download.retryCount) : \(download.remoteURL)")
        }

        os_log(verbosity: configuration.logVerbosity, type: .debug, format: "Did complete: %@", args: download.remoteURL.lastPathComponent)
        #if DEBUG
        showLocalNotification(defaultText: "did complete \(download.remoteURL.lastPathComponent)")
        #endif
    }

    private func rescheduleDownload(resumeData: Data?, downloadItem: DownloadItem) -> Bool {
        guard downloadItem.retryCount < configuration.maximumRetries else {
            if configuration.usesNotificationCenter {
                NotificationCenter.default.post(name: .downloadFailed, object: downloadItem.remoteURL)
            }
            return false
        }

        downloadItem.retryCount += 1
        backingStore.saveDownloadItem(downloadItem)

        let task: URLSessionDownloadTask

        if let resumeData = resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: downloadItem.remoteURL)
        }
        task.earliestBeginDate = Date().addingTimeInterval(TimeInterval(downloadItem.retryCount * configuration.exponentialBackoffMultiplier))

        task.resume()

        os_log(verbosity: configuration.logVerbosity, type: .debug, format: "Rescheduled: %@ retrycount: %d", args: downloadItem.remoteURL.lastPathComponent, downloadItem.retryCount)

        #if DEBUG
        showLocalNotification(defaultText: "Rescheduled: \(downloadItem.remoteURL.lastPathComponent)")
        #endif
        if configuration.usesNotificationCenter {
            NotificationCenter.default.post(name: .downloadAddedToQueue, object: downloadItem.remoteURL)
        }

        return true
    }

    #if !os(macOS)
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        session.getTasksWithCompletionHandler { _, _, downloadTasks in
            if downloadTasks.isEmpty {
                OperationQueue.main.addOperation {
                    if let completion = self.backgroundDownloadCompletionHandler {
                        completion()
                    }

                    #if DEBUG
                    self.showLocalNotification(defaultText: "All downloads complete")
                    #endif
                    self.backingStore.deleteAll()
                    self.backgroundDownloadCompletionHandler = nil
                }
            }
        }
    }
    #endif

    // MARK: - Local Notifications -

    private func showLocalNotification(defaultText: String) {
        guard configuration.showsLocalNotifications else {
            return
        }
        var notificationText = defaultText
        if let userNotificationText = localNotificationText {
            notificationText = userNotificationText
        }

        showLocalNotification(text: notificationText)
    }

    private func showLocalNotification(text: String) {
        guard configuration.showsLocalNotifications else {
            return
        }
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                os_log(verbosity: self.configuration.logVerbosity, type: .error, format: "Not authorized to schedule notification")
                debugPrint("Not authorized to schedule notification")
                return
            }

            let content = UNMutableNotificationContent()
            #if !os(tvOS)
            content.title = text
            content.sound = UNNotificationSound.default
            #endif
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let identifier = "DownloadManagerNotification"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            notificationCenter.add(request, withCompletionHandler: { error in
                if let error = error {
                    os_log(verbosity: self.configuration.logVerbosity, type: .error, format: "Could not schedule notification %@", args: error.localizedDescription)
                    debugPrint("Could not schedule notification, error : \(error)")
                }
            })
        }
    }
}
