//
//  SabaDownloadModel.swift
//  SabaDownloadManager
//
//  Created by Muhammad Zeeshan on 19/04/2016.
//  Copyright © 2016 ideamakerz. All rights reserved.
//

import Foundation

public enum TaskStatus: Int {
    case unknown, gettingInfo, downloading, paused, failed, inQueue, finished
    
    public func description() -> String {
        switch self {
        case .gettingInfo:
            return "GettingInfo"
        case .downloading:
            return "Downloading"
        case .paused:
            return "Paused"
        case .failed:
            return "Failed"
        case .inQueue:
            return "InQueue"
        case .finished:
            return "Finished"
        default:
            return "Unknown"
        }
    }
}

open class SabaDownloadModel: NSObject {
    
    open var fileName: String!
    open var fileURL: String!
    open var status: String = TaskStatus.inQueue.description()
    
    open var file: (size: Float, unit: String)?
    open var downloadedFile: (size: Float, unit: String)?
    
    open var remainingTime: (hours: Int, minutes: Int, seconds: Int)?
    
    open var speed: (speed: Float, unit: String)?
    
    open var progress: Float = 0
    
    open var task: URLSessionDownloadTask?
    
    open var startTime: Date?
    
    fileprivate(set) open var destinationPath: String = ""
    
    fileprivate convenience init(fileName: String, fileURL: String) {
        self.init()
        
        self.fileName = fileName
        self.fileURL = fileURL
    }
    
    convenience init(fileName: String, fileURL: String, destinationPath: String) {
        self.init(fileName: fileName, fileURL: fileURL)
        
        self.destinationPath = destinationPath
    }
}
