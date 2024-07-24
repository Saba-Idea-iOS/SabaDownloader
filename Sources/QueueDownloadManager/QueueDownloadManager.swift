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
//        print("*********> operationCount > \(queue.operationCount)")
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
            print("taskName5 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
            if downloadTask.isEqual(downloadModel.task) {
                print("taskName6 ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
                let fileName = downloadModel.fileName as NSString
                let basePath = downloadModel.destinationPath == "" ? SabaDownloadUtility.baseFilePath : downloadModel.destinationPath
                let destinationPath = (basePath as NSString).appendingPathComponent(fileName as String)
                
                let fileManager : FileManager = FileManager.default
                
                //If all set just move downloaded file to the destination
                if fileManager.fileExists(atPath: basePath) {
                    let fileURL = URL(fileURLWithPath: destinationPath as String)
                    debugPrint("directory path = \(destinationPath)")
                    
                    do {
                        try fileManager.moveItem(at: location, to: fileURL)
                    } catch let error as NSError {
                        debugPrint("Error while moving downloaded file to destination path:\(error)")
                        DispatchQueue.main.async(execute: { () -> Void in
                            self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel, index: index)
                        })
                    }
                } else {
                    //Opportunity to handle the folder doesnot exists error appropriately.
                    //Move downloaded file to destination
                    //Delegate will be called on the session queue
                    //Otherwise blindly give error Destination folder does not exists
                    
                    print("taskName7 ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
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
        debugPrint("task id: \(task.taskDescription ?? "-")")
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
                print("taskName4 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                print("downloadModel.status1 ------->\(downloadModel.status)")
                if downloadModel.status != TaskStatus.paused.description() {
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
                print("taskName3 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                
                guard downloadModel.status != TaskStatus.paused.description() else {
                    return
                }
                
                self.delegate?.downloadRequestDidPopulatedInterruptedTasks(self.downloadingArray)
                
                print("------> continueeeee")
                self.checkQueue()
                
            } else {
//                print("error -----> \(String(describing: error))")
                for(index, object) in self.downloadingArray.enumerated() {
                    let downloadModel = object
                    if task.isEqual(downloadModel.task) {
                        if err?.code == NSURLErrorCancelled || err == nil {
                            self.downloadingArray.remove(at: index)
                            print("taskName1 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                            if err == nil {
                                self.delegate?.downloadRequestFinished?(downloadModel, index: index)
                                for (index, task) in self.queue.enumerated() {
                                    if task.taskDescription == String(downloadModel.task?.taskDescription ?? "-") {
//                                        task.cancel()
                                        self.queue.remove(at: index)
                                    }
                                }
                                self.checkQueue()
                            } else {
                                print("taskName8 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                                self.delegate?.downloadRequestCanceled?(downloadModel, index: index)
                                self.checkQueue()
                            }
                            
                        } else {
                            
                            print("taskName2 ---------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                            print("downloadModel.status2 ------->\(downloadModel.status)")
                            let resumeData = err?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                            var newTask = task
                            if self.isValidResumeData(resumeData) == true {
                                newTask = self.sessionManager.downloadTask(withResumeData: resumeData!)
                            } else {
                                newTask = self.sessionManager.downloadTask(with: URL(string: downloadModel.fileURL)!)
                            }
                            print("task Description ---------->\(task.taskDescription?.suffix(10) ?? "")")
                            newTask.taskDescription = task.taskDescription
                            if downloadModel.status == TaskStatus.downloading.description() {
                                downloadModel.status = TaskStatus.failed.description()
                            }
                            downloadModel.task = newTask as? URLSessionDownloadTask
                            
                            self.downloadingArray[index] = downloadModel
                            
                            if downloadModel.status != TaskStatus.downloading.description() {
                                print("taskName116565 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                                downloadModel.status = TaskStatus.paused.description()
                                self.downloadingArray[index] = downloadModel
                                self.delegate?.downloadRequestDidPaused?(downloadModel, index: index)
                                return
                            }
                            print("taskName11 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                            if let error = err {
                                print("taskName12 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
                                print("downloadRequestDidFailedWithError ------->\(downloadModel.status)")
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel,
                                                                                  index: index)
                            } else {
                                print("taskName13 ----------->\(downloadModel.task?.taskDescription?.suffix(10) ?? "-")")
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
        debugPrint("All tasks are finished")
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
        downloadTask.suspend()
        let downloadModel = SabaDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
        downloadModel.startTime = Date()
        downloadModel.status = TaskStatus.waiting.description()
        downloadModel.task = downloadTask
        downloadingArray.append(downloadModel)
        delegate?.downloadRequestQueued?(downloadModel, index: downloadingArray.count - 1)
        print("taskdes - add ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
        self.queue.append(downloadTask)
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
        downloadTask.suspend()
        let downloadModel = SabaDownloadModel.init(fileName: fileName,
                                                   fileURL: fileURL,
                                                   destinationPath: destinationPath)
        print("------> \(downloadTask.taskDescription ?? "")")
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
        print("taskdes - pause ----------->\(downloadTask?.taskDescription?.suffix(10) ?? "-")")
        downloadModel.status = TaskStatus.paused.description()
        let task = queue.first(where: {
            $0.taskDescription == String(downloadModel.task?.taskDescription ?? "")
        })
        let taskDescription = task?.taskDescription ?? ""
        print("taskDescription ----------->\(taskDescription)")
        task?.suspend()
        queue.removeAll(where: {
            $0.taskDescription == String(downloadModel.task?.taskDescription ?? "")
        })
        downloadTask?.suspend()
        downloadModel.task = downloadTask
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
            print("resume-")
            return
        }
        downloadModel.status = TaskStatus.waiting.description()
        if let downloadTask = downloadModel.task {
            print("taskdes-resume ----------->\(downloadTask.taskDescription?.suffix(10) ?? "-")")
            downloadTask.suspend()
            queue.append(downloadTask)
            downloadModel.task = downloadTask
        }
        
        downloadingArray[index] = downloadModel
        delegate?.downloadRequestQueued?(downloadModel, index: index)
        checkQueue()
    }
    
    @objc public func retryDownloadTaskAtIndex(_ index: Int) {
        print("-----> retry1")
        let downloadModel = downloadingArray[index]
        let downloadTask = downloadModel.task
        guard let task =
                queue.first(where: {
                    $0.taskDescription == String(downloadTask?.taskDescription ?? "-")
                }),
              task.state == .running else {
            return
        }
        print("-----> retry2")
        downloadTask!.resume()
        downloadModel.status = TaskStatus.downloading.description()
        downloadModel.task = downloadTask
        downloadingArray[index] = downloadModel
    }
    
    @objc public func cancelTaskAtIndex(_ index: Int) {
        let downloadInfo = downloadingArray[index]
        let downloadTask = downloadInfo.task
        for (idx, task) in queue.enumerated() {
            if task.taskDescription == String(downloadTask?.taskDescription ?? "-") {
                downloadTask?.cancel()
                queue.remove(at: idx)
            }
        }
        checkQueue()
    }
    
    func checkQueue() {
        defer {
            lock.unlock()
        }
        lock.lock()
        queue = queue.compactMap({ $0 })
        for (idx, _) in queue.enumerated() {
            if queue.filter({ $0.state == .running }).isEmpty,
               let firstTask = queue.first {
                if let index = downloadingArray.firstIndex(where: {
                    $0.task?.taskDescription == firstTask.taskDescription
                }) {
                    let downloadModel = downloadingArray[index]
                    if let request = downloadModel.task?.currentRequest {
                        let downloadTask = sessionManager.downloadTask(with: request)
                        downloadTask.resume()
                        downloadTask.taskDescription = downloadModel.task?.taskDescription
                        downloadTask.progress.resume()
                        downloadModel.task = downloadTask
                        queue[idx] = downloadTask
                    }
                    downloadModel.status = TaskStatus.downloading.description()
                    downloadingArray[index] = downloadModel
                    delegate?.downloadRequestDidResumed?(downloadModel, index: index)
                }
            }
        }
    }
    
    func checkMoreThanOneRunning() {
        if queue.filter({ $0.state == .running }).count > 1 {
            if let index = downloadingArray.firstIndex(where: {
                $0.task?.taskDescription == queue[1].taskDescription
            }) {
                queue[1].suspend()
                let downloadModel = self.downloadingArray[index]
                downloadModel.status = TaskStatus.waiting.description()
                if let downloadTask = downloadModel.task {
                    downloadTask.suspend()
                    queue.append(downloadTask)
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
