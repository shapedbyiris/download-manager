//
//  FileSystem.swift
//
//  Created by Gabriel Nica on 06/08/2019.
//  Copyright © 2019 Shaped by Iris. All rights reserved.

import Foundation

extension FileManager {
    func moveFile(at url: URL,
                  toDocumentsDirectoryUnder directory: String?,
                  renameTo name: String?, overwrite: Bool = true) throws -> URL
    { // swiftlint:disable:this opening_brace
        var newUrl: URL

        if let directory = directory {
            let directoryUrl = documentsDirectoryURL().appendingPathComponent(directory)
            if fileExists(atPath: directoryUrl.path) == false {
                try createDirectory(at: directoryUrl, withIntermediateDirectories: true, attributes: nil)
            }

            newUrl = directoryUrl
        } else {
            newUrl = documentsDirectoryURL()
        }

        if let name = name {
            newUrl = newUrl.appendingPathComponent(name)
        } else {
            newUrl = newUrl.appendingPathComponent(url.lastPathComponent)
        }

        if fileExists(atPath: newUrl.path), overwrite {
            try removeItem(at: newUrl)
        }

        try moveItem(at: url, to: newUrl)

        return newUrl
    }

    func moveFile(at url: URL, to destinationURL: URL, fileName: String, overwrite: Bool = true) throws -> URL {
        var isDirectory: ObjCBool = false

        var finalDestinationURL = destinationURL

        if fileExists(atPath: destinationURL.path, isDirectory: &isDirectory), isDirectory.boolValue == true {
            finalDestinationURL.appendPathComponent(fileName)
        }

        if fileExists(atPath: finalDestinationURL.path), overwrite {
            try removeItem(at: finalDestinationURL)
        }

        try moveItem(at: url, to: finalDestinationURL)

        return finalDestinationURL
    }

    public func documentsDirectoryURL() -> URL {
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: path)
    }

    public func temporaryDirectoryURL() -> URL {
        let path = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: path)
    }
}
