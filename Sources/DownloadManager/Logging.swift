//
//  Logging.swift
//
//  Created by Gabriel Nica on 07/08/2019.
//  Copyright © 2019 Shaped by Iris. All rights reserved.

import Foundation
import os

private let productName = (Bundle.main.infoDictionary![kCFBundleNameKey as String] as? String) ?? "DownloadManager"

let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: productName)

public enum LogVerbosity {
    case none
    case debug
    case error

    var oslogtype: OSLogType {
        switch self {
        case .none:
            return .default
        case .debug:
            return .debug
        case .error:
            return .error
        }
    }
}

func os_log(verbosity: LogVerbosity, type: OSLogType, format: StaticString, args: CVarArg ...) {
    guard verbosity != .none, verbosity.oslogtype == type else {
        return
    }

    os_log(format, log: log, type: type, args)
}
