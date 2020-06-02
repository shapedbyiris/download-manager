# Download Manager

Swift download manager that can initiate, cancel, resume and persist downloads between app sessions on all Apple platforms as well as download files in background for iOS

## Usage

```swift
import Foundation
import DownloadManager

let fileURLToDownload = URL(string: "url of file to download")

// if destinationURL is nil then the DownloadManager will place the downloaded file 
// in the device's temporary directory
DownloadManager.shared.addDownload(url: fileURLToDownload, destinationURL: nil, onCompletion: { error, fileURL in
    guard error == nil else {
        // handle error
    }
    
    // fileURL is the local file URL on the device
    print(fileURL)
})
```

If you want to report progress add a progress handler to the download

```swift

let fileURLToDownload = URL(string: "url of file to download")

DownloadManager.shared.addDownload(url: fileURLToDownload, destinationURL: nil,
                                   onProgress: { progress in
                                       // progress is a Float
                                       print(String(format: "%.0f%% complete", progress))
                                   }, onCompletion: { error, fileURL in
                                       guard error == nil else {
                                           // handle error
                                       }

                                       // fileURL is the local file URL on the device
                                       print(fileURL)
})
```

## Canceling ongoing downloads

You can either cancel all ongoing downloads using 
```swift
DownloadManager.shared.cancelAllDownloads()
```

or individually using
```swift
DownloadManager.shared.cancelDownload(withURL: urlToCancel)
```

## Configuration

The download manager can be configured at any time however results are best when configured before downloads are initiated. Existing downloads will not update their internal configuration for settings such as retry count.

The download manager is configured using the following structure:
```swift
public struct DownloadManagerConfig {
    public var maximumRetries = 3
    public var exponentialBackoffMultiplier = 10
    public var usesNotificationCenter = false
    public var showsLocalNotifications = false
    public var logVerbosity: LogVerbosity = .none
}
```

```swift
DownloadManager.shared.configuration = DownloadManagerConfiguration()
```
| Property | Description |
| :---------- | :------------- |
`maximumRetries` | the manager will retry each download this number of times until it will trigger a failure
`exponentialBackoffMultiplier` | each time a download is retried it is rescheduled after an increasing number of seconds: `maximumRetries * exponentialBackoffMultiplier`
`usesNotificationCenter` | if true, the Download Manager will also send notifications via NotificationCenter for download events
`showsLocalNotifications` | currently a debugging feature and needs Info.plist support to show a local notification for download events. Useful for background downloads. 
`logVerbosity` | by default the manager doesn't output any logs to console as they can be quite verbose. To change this use one of `.none`, `debug` | all messages including progress, `error` - only errors are logged to console

## Notifications

if the manager has been configured for sending notifications, the following notifications are available:

```swift
public extension Notification.Name {
    static let downloadAddedToQueue = Notification.Name("com.shapedbyiris.downloadAddedToQueue")
    static let downloadRemovedFromQueue = Notification.Name("com.shapedbyiris.downloadRemovedFromQueue")
    static let downloadFinished = Notification.Name("com.shapedbyiris.downloadFinished")
    static let downloadProgress = Notification.Name("com.shapedbyiris.downloadProgress")
    static let downloadFailed = Notification.Name("com.shapedbyiris.downloadFailed")
}
```

All notifications will be sent with the `object` property filled with the following:

| Notification Name | `object` contains |
| :---------- | :------------- |
`downloadAddedToQueue` | url added to the download queue
`downloadRemovedFromQueue` | url removed from the download queue. This could be from a cancellation, completion or failure
`downloadFinished` | a tuple consisting of `(locallyDownloadedFileURL, remoteURL)`
`downloadProgress` | a tuple consisting of `(progress, remoteURL)`, where progress is a Float
`downloadFailed` | url that failed to download after `DownloadManagerConfig.maximumRetries`

## Background downloads (iOS)

The Download Manager can continue downloads while the app is in background. 
Different app states affect how your app interacts with the background download. In iOS, your app could be in the foreground, suspended, or even terminated by the system

As per `https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background` you need to manually save the system completion handler for background URL session events and pass it on to the Download Manager

```swift
func application(_ application: UIApplication,
                 handleEventsForBackgroundURLSession identifier: String,
                 completionHandler: @escaping () -> Void) {
    DownloadManager.shared.backgroundDownloadCompletionHandler = completionHandler
}
```

If the system terminated the app while it was suspended, the system relaunches the app in the background. In this case completion and progress handlers will not be executed so it is best to use Notification Center for events 


## Instalation

### Swift Package Manager

Add the package through the built in interface in Xcode 11+ or

In `Packages.swift`:
```swift
// Add this line in the `dependencies` array:
.package(url: "https://github.com/shapedbyiris/download-manager.git", from: "0.1.0")

// Add Download Manager to your target's dependencies:
.dependencies: ["DownloadManager"]
```

Then run
```bash
swift package update
```
