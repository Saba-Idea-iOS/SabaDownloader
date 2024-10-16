//
//  QueueDownloadManager.swift
//  QueueDownloadManager
//
//  Created by Muhammad Zeeshan on 19/04/2016.
//  Copyright © 2016 ideamakerz. All rights reserved.
//

import Foundation
import SabaDownloader

#if os(iOS)
import UIKit
#endif
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l > r
    default:
        return rhs < lhs
    }
}
public class QueueDownloadManager: NSObject, SabaDownloadManagerProtocol {
    fileprivate var sessionManager: URLSession!
    fileprivate var backgroundSessionCompletionHandler: (() -> Void)?
    fileprivate let TaskDescFileNameIndex = 0
    fileprivate let TaskDescFileURLIndex = 1
    fileprivate let TaskDescFileDestinationIndex = 2
    fileprivate weak var delegate: SabaDownloadManagerDelegate?
    let lock = NSLock()
    open var downloadingArray: [SabaDownloadModel] = []
    var queue = [URLSessionDownloadTask]()
    /// Initializer for foreground downloader only
    /// - Parameters:
    required public convenience init(delegate: SabaDownloadManagerDelegate, sessionConfiguration: URLSessionConfiguration, completion: (() -> Void)? = nil) {
        self.init()
        self.delegate = delegate
        self.sessionManager = .init(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        self.backgroundSessionCompletionHandler = completion
    }
    
    /// Default init which covers background mode as well
    /// - Parameters:
    ///   - sessionIdentifer: <#sessionIdentifer description#>
    ///   - delegate: <#delegate description#>
    ///   - sessionConfiguration: <#sessionConfiguration description#>
    ///   - completion: <#completion description#>
    required public convenience init(session sessionIdentifer: String, delegate: SabaDownloadManagerDelegate, sessionConfiguration: URLSessionConfiguration? = nil, completion: (() -> Void)? = nil) {
        self.init()
        self.delegate = delegate
        self.sessionManager = backgroundSession(identifier: sessionIdentifer, configuration: sessionConfiguration)
        self.backgroundSessionCompletionHandler = completion
    }
    
    public class func defaultSessionConfiguration(identifier: String) -> URLSessionConfiguration {
        return URLSessionConfiguration.background(withIdentifier: identifier)
    }
    
    fileprivate func backgroundSession(identifier: String, configuration: URLSessionConfiguration? = nil) -> URLSession {
        let sessionConfiguration = configuration ?? SabaDownloadManager.defaultSessionConfiguration(identifier: identifier)
        assert(identifier == sessionConfiguration.identifier, "Configuration identifiers do not match")
        let session = Foundation.URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        return session
    }
}

// MARK: Private Helper functions
extension QueueDownloadManager {
    fileprivate func isValidResumeData(_ resumeData: Data?) -> Bool {
        guard resumeData != nil || resumeData?.count > 0 else {
            return false
        }
        return true
    }
}

extension QueueDownloadManager: URLSessionDownloadDelegate {
    
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        for (index, downloadModel) in self.downloadingArray.enumerated() {
            if downloadTask.isEqual(downloadModel.task) {
                DispatchQueue.main.async(execute: { () -> Void in
                    
                    let receivedBytesCount = Double(downloadTask.countOfBytesReceived)
                    let totalBytesCount = Double(downloadTask.countOfBytesExpectedToReceive)
                    let progress = Float(receivedBytesCount / totalBytesCount)
                    
                    let taskStartedDate = downloadModel.startTime
                    let timeInterval = taskStartedDate?.timeIntervalSinceNow ?? 60
                    let downloadTime = TimeInterval(-1 * timeInterval)
                    
                    let speed = Float(totalBytesWritten) / Float(downloadTime)
                    
                    let remainingContentLength = totalBytesExpectedToWrite - totalBytesWritten
                    
                    let remainingTime = remainingContentLength / Int64(speed)
                    let hours = Int(remainingTime) / 3600
                    let minutes = (Int(remainingTime) - hours * 3600) / 60
                    let seconds = Int(remainingTime) - hours * 3600 - minutes * 60
                    
                    let totalFileSize = SabaDownloadUtility.calculateFileSizeInUnit(totalBytesExpectedToWrite)
                    let totalFileSizeUnit = SabaDownloadUtility.calculateUnit(totalBytesExpectedToWrite)
                    
                    let downloadedFileSize = SabaDownloadUtility.calculateFileSizeInUnit(totalBytesWritten)
                    let downloadedSizeUnit = SabaDownloadUtility.calculateUnit(totalBytesWritten)
                    
                    let speedSize = SabaDownloadUtility.calculateFileSizeInUnit(Int64(speed))
                    let speedUnit = SabaDownloadUtility.calculateUnit(Int64(speed))
                    
                    downloadModel.remainingTime = (hours, minutes, seconds)
                    downloadModel.file = (totalFileSize, totalFileSizeUnit as String)
                    downloadModel.downloadedFile = (downloadedFileSize, downloadedSizeUnit as String)
                    downloadModel.speed = (speedSize, speedUnit as String)
                    downloadModel.progress = progress
                    downloadModel.status = TaskStatus.downloading.description()
                    
                    if self.downloadingArray.contains(downloadModel), let objectIndex = self.downloadingArray.firstIndex(of: downloadModel) {
                        self.downloadingArray[objectIndex] = downloadModel
                    }
                    self.delegate?.downloadRequestDidUpdateProgress(downloadModel, index: index)
                })
                break
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        for (index, downloadModel) in downloadingArray.enumerated() {
            printIfDebug("taskName5 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
            if downloadTask.isEqual(downloadModel.task) {
                printIfDebug("taskName6 ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
                let fileName = downloadModel.fileName as NSString
                let basePath = downloadModel.destinationPath == "" ? SabaDownloadUtility.baseFilePath : downloadModel.destinationPath
                let destinationPath = (basePath as NSString).appendingPathComponent(fileName as String)
                
                let fileManager : FileManager = FileManager.default
                
                //If all set just move downloaded file to the destination
                if fileManager.fileExists(atPath: basePath) {
                    let fileURL = URL(fileURLWithPath: destinationPath as String)
                    printIfDebug("directory path = \(destinationPath)")
                    
                    do {
                        try fileManager.moveItem(at: location, to: fileURL)
                    } catch let error as NSError {
                        printIfDebug("Error while moving downloaded file to destination path:\(error)")
                        DispatchQueue.main.async(execute: { () -> Void in
                            self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel, index: index)
                        })
                    }
                } else {
                    //Opportunity to handle the folder doesnot exists error appropriately.
                    //Move downloaded file to destination
                    //Delegate will be called on the session queue
                    //Otherwise blindly give error Destination folder does not exists
                    
                    printIfDebug("taskName7 ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
                    if let _ = self.delegate?.downloadRequestDestinationDoestNotExists {
                        self.delegate?.downloadRequestDestinationDoestNotExists?(downloadModel, index: index, location: location)
                    } else {
                        let error = NSError(domain: "FolderDoesNotExist", code: 404, userInfo: [NSLocalizedDescriptionKey : "Destination folder does not exists"])
                        self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel, index: index)
                    }
                }
                
                break
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        printIfDebug("task id: \(task.taskDescription ?? "-")")
        /***** Any interrupted tasks due to any reason will be populated in failed state after init *****/
        DispatchQueue.main.async {
            
            let err = error as NSError?
            
            if (err?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? NSNumber)?.intValue == NSURLErrorCancelledReasonUserForceQuitApplication || (err?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? NSNumber)?.intValue == NSURLErrorCancelledReasonBackgroundUpdatesDisabled {
                let downloadTask = task as! URLSessionDownloadTask
                let taskDescComponents: [String] = downloadTask.taskDescription!.components(separatedBy: ",")
                let fileName = taskDescComponents[self.TaskDescFileNameIndex]
                let fileURL = taskDescComponents[self.TaskDescFileURLIndex]
                let destinationPath = taskDescComponents[self.TaskDescFileDestinationIndex]
                
                let downloadModel = SabaDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
                printIfDebug("taskName4 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                printIfDebug("downloadModel.status1 ------->\(downloadModel.status)")
                if downloadModel.status == TaskStatus.downloading.description() {
                    downloadModel.status = TaskStatus.failed.description()
                }
                downloadModel.task = downloadTask
                
                let resumeData = err?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                
                var newTask = downloadTask
                if self.isValidResumeData(resumeData) == true {
                    newTask = self.sessionManager.downloadTask(withResumeData: resumeData!)
                } else {
                    newTask = self.sessionManager.downloadTask(with: URL(string: fileURL as String)!)
                }
                
                newTask.taskDescription = downloadTask.taskDescription
                downloadModel.task = newTask
                
                self.downloadingArray.append(downloadModel)
                printIfDebug("taskName3 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                
                guard downloadModel.status != TaskStatus.paused.description() else {
                    return
                }
                
                self.delegate?.downloadRequestDidPopulatedInterruptedTasks(self.downloadingArray)
                
                printIfDebug("------> continueeeee")
                self.checkQueue()
                
            } else {
//                printIfDebug("error -----> \(String(describing: error))")
                for(index, object) in self.downloadingArray.enumerated() {
                    let downloadModel = object
                    if task.isEqual(downloadModel.task) {
                        if err?.code == NSURLErrorCancelled || err == nil {
                            self.downloadingArray.remove(at: index)
                            printIfDebug("taskName1 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                            if err == nil {
                                self.delegate?.downloadRequestFinished?(downloadModel, index: index)
                                self.queue.removeAll(where: {
                                    $0.taskDescription == String(downloadModel.task?.taskDescription ?? "")
                                })
                                self.checkQueue()
                            } else {
                                printIfDebug("taskName8 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                                self.delegate?.downloadRequestCanceled?(downloadModel, index: index)
                                self.checkQueue()
                            }
                            
                        } else {
                            
                            printIfDebug("taskName2 ---------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                            printIfDebug("downloadModel.status2 ------->\(downloadModel.status)")
                            let resumeData = err?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                            var newTask = task
                            if self.isValidResumeData(resumeData) == true {
                                newTask = self.sessionManager.downloadTask(withResumeData: resumeData!)
                            } else {
                                newTask = self.sessionManager.downloadTask(with: URL(string: downloadModel.fileURL)!)
                            }
                            printIfDebug("task Description ---------->\(task.taskDescription?.suffix(10) ?? "")")
                            newTask.taskDescription = task.taskDescription
                            if downloadModel.status == TaskStatus.downloading.description() {
                                downloadModel.status = TaskStatus.failed.description()
                            }
                            downloadModel.task = newTask as? URLSessionDownloadTask
                            
                            self.downloadingArray[index] = downloadModel
                            
                            if downloadModel.status != TaskStatus.downloading.description() {
                                printIfDebug("taskName116565 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                                downloadModel.status = TaskStatus.paused.description()
                                self.downloadingArray[index] = downloadModel
                                self.delegate?.downloadRequestDidPaused?(downloadModel, index: index)
                                return
                            }
                            printIfDebug("taskName11 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                            if let error = err {
                                printIfDebug("taskName12 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                                printIfDebug("downloadRequestDidFailedWithError ------->\(downloadModel.status)")
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel,
                                                                                  index: index)
                            } else {
                                printIfDebug("taskName13 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                                let error: NSError = NSError(domain: "SabaDownloadManagerDomain", code: 1000, userInfo: [NSLocalizedDescriptionKey : "Unknown error occurred"])
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel, index: index)
                            }
                        }
                        break
                    }
                }
            }
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let backgroundCompletion = self.backgroundSessionCompletionHandler {
            DispatchQueue.main.async(execute: {
                backgroundCompletion()
            })
        }
        printIfDebug("All tasks are finished")
    }
}

//MARK: Public Helper Functions
extension QueueDownloadManager {
    @objc
    public func addDownloadTask(_ fileName: String,
                                request: URLRequest,
                                destinationPath: String) {
        let url = request.url!
        let fileURL = url.absoluteString
        
        let downloadTask = sessionManager.downloadTask(with: request)
        downloadTask.taskDescription = [fileName, fileURL, destinationPath].joined(separator: ",")
        downloadTask.progress.pause()
        let downloadModel = SabaDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
        downloadModel.startTime = Date()
        downloadModel.status = TaskStatus.waiting.description()
        downloadModel.task = downloadTask
        downloadingArray.append(downloadModel)
        delegate?.downloadRequestQueued?(downloadModel, index: downloadingArray.count - 1)
        printIfDebug("taskdes - add ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
        self.queue.append(downloadTask.copy() as! URLSessionDownloadTask)
        checkQueue()
    }
    
    @objc
    public func addDownloadArray(_ fileName: String,
                                request: URLRequest,
                                destinationPath: String,
                                status: String) {
        let url = request.url!
        let fileURL = url.absoluteString
        
        let downloadTask = self.sessionManager.downloadTask(with: request)
        downloadTask.taskDescription = [fileName, fileURL, destinationPath].joined(separator: ",")
        downloadTask.progress.pause()
        let downloadModel = SabaDownloadModel.init(fileName: fileName,
                                                   fileURL: fileURL,
                                                   destinationPath: destinationPath)
        printIfDebug("------> \(downloadTask.taskDescription ?? "")")
        downloadModel.startTime = Date()
        downloadModel.status = status
        downloadModel.task = downloadTask
        
        self.downloadingArray.append(downloadModel)
        let index = self.downloadingArray.count - 1
        self.delegate?.downloadRequestDidPaused?(downloadModel, index: index)
    }
    
    @objc public func pauseDownloadTaskAtIndex(_ index: Int) {
        lock.lock()
        let downloadModel = downloadingArray[index]
        let downloadTask = downloadModel.task
        printIfDebug("taskdes - pause ----------->\(downloadTask?.taskDescription?.suffix(10) ?? "-")")
        downloadModel.status = TaskStatus.paused.description()
        queue.removeAll(where: {
            $0.taskDescription == String(downloadModel.task?.taskDescription ?? "")
        })
        queue.removeAll(where: { $0.taskDescription == "" })
        downloadTask?.suspend()
        downloadingArray[index] = downloadModel
        delegate?.downloadRequestDidPaused?(downloadModel, index: index)
        lock.unlock()
        if !queue.isEmpty {
            checkQueue()
        }
    }
   
    @objc public func resumeDownloadTaskAtIndex(_ index: Int) {
        let downloadModel = self.downloadingArray[index]
        guard downloadModel.status != TaskStatus.downloading.description() else {
            printIfDebug("resume-")
            return
        }
        downloadModel.status = TaskStatus.waiting.description()
        if let downloadTask = downloadModel.task {
            printIfDebug("taskdes-resume ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
            downloadTask.suspend()
            queue.append(downloadTask.copy() as! URLSessionDownloadTask)
        }
        downloadingArray[index] = downloadModel
        delegate?.downloadRequestQueued?(downloadModel, index: index)
        checkQueue()
    }
    
    @objc public func retryDownloadTaskAtIndex(_ index: Int) {
        printIfDebug("-----> retry1")
        let downloadModel = downloadingArray[index]
        let downloadTask = downloadModel.task
        guard let task =
                queue.first(where: {
                    $0.taskDescription == String(downloadTask?.taskDescription ?? "-")
                }),
              task.state == .running else {
            return
        }
        printIfDebug("-----> retry2")
        downloadTask!.resume()
        downloadModel.status = TaskStatus.downloading.description()
        downloadModel.task = downloadTask
        downloadingArray[index] = downloadModel
    }
    
    @objc public func cancelTaskAtIndex(_ index: Int) {
        let downloadInfo = downloadingArray[index]
        let downloadTask = downloadInfo.task
        downloadTask?.cancel()
        self.queue.removeAll(where: {
            $0.taskDescription == String(downloadTask?.taskDescription ?? "")
        })
        checkQueue()
    }
    
    func checkQueue() {
        defer {
            lock.unlock()
        }
        lock.lock()
        queue = queue.compactMap({ $0 })
        if queue.filter({ $0.state == .running }).isEmpty,
           var firstTask = queue.first {
            if let index = downloadingArray.firstIndex(where: {
                $0.task?.taskDescription == firstTask.taskDescription
            }) {
                let downloadModel = downloadingArray[index]
                let downloadTask = downloadModel.task
                downloadTask?.resume()
                downloadTask?.progress.resume()
                downloadModel.status = TaskStatus.downloading.description()
                downloadingArray[index] = downloadModel
                delegate?.downloadRequestDidResumed?(downloadModel, index: index)
                firstTask = downloadTask!.copy() as! URLSessionDownloadTask
            }
        }
    }
    
    func checkMoreThanOneRunning() {
        if queue.filter({ $0.state == .running }).count > 1 {
            if let index = downloadingArray.firstIndex(where: {
                $0.task?.taskDescription == queue.first?.taskDescription ?? ""
            }) {
                queue.first?.suspend()
                let downloadModel = self.downloadingArray[index]
                downloadModel.status = TaskStatus.waiting.description()
                if let downloadTask = downloadModel.task {
                    downloadTask.suspend()
                    queue.append(downloadTask.copy() as! URLSessionDownloadTask)
                    downloadModel.task = downloadTask
                }
                downloadingArray[index] = downloadModel
                delegate?.downloadRequestQueued?(downloadModel, index: index)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.checkMoreThanOneRunning()
        }
    }
    
#if os(iOS)
    @objc public func presentNotificationForDownload(_ notifAction: String, notifBody: String) {
        let application = UIApplication.shared
        let applicationState = application.applicationState
        
        if applicationState == UIApplication.State.background {
            let localNotification = UILocalNotification()
            localNotification.alertBody = notifBody
            localNotification.alertAction = notifAction
            localNotification.soundName = UILocalNotificationDefaultSoundName
            localNotification.applicationIconBadgeNumber += 1
            application.presentLocalNotificationNow(localNotification)
        }
    }
#endif
}
