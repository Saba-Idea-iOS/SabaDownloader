//
//  SabaDownloadManager.swift
//  SabaDownloadManager
//
//  Created by Muhammad Zeeshan on 19/04/2016.
//  Copyright © 2016 ideamakerz. All rights reserved.
//

import Foundation
import Queuer

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
@objc public protocol SabaDownloadManagerDelegate: AnyObject {
    /**A delegate method called each time whenever any download task's progress is updated
     */
    @objc func downloadRequestDidUpdateProgress(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called when interrupted tasks are repopulated
     */
    @objc func downloadRequestDidPopulatedInterruptedTasks(_ downloadModel: [SabaDownloadModel])
    /**A delegate method called each time whenever new download task is start downloading
     */
    @objc optional func downloadRequestQueued(_ downloadModel: SabaDownloadModel, index: Int)
    @objc optional func downloadRequestStarted(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever running download task is paused. If task is already paused the action will be ignored
     */
    @objc optional func downloadRequestDidPaused(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever any download task is resumed. If task is already downloading the action will be ignored
     */ 
    @objc optional func downloadRequestDidOtherPaused(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever any download task is resumed. If task is already downloading the action will be ignored
     */
    @objc optional func downloadRequestDidResumed(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever any download task is resumed. If task is already downloading the action will be ignored
     */
    @objc optional func downloadRequestDidRetry(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever any download task is cancelled by the user
     */
    @objc optional func downloadRequestCanceled(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever any download task is finished successfully
     */
    @objc optional func downloadRequestFinished(_ downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever any download task is failed due to any reason
     */
    @objc optional func downloadRequestDidFailedWithError(_ error: NSError, downloadModel: SabaDownloadModel, index: Int)
    /**A delegate method called each time whenever specified destination does not exists. It will be called on the session queue. It provides the opportunity to handle error appropriately
     */
    @objc optional func downloadRequestDestinationDoestNotExists(_ downloadModel: SabaDownloadModel, index: Int, location: URL)
    
}

open class SabaDownloadManager: NSObject {
    fileprivate var sessionManager: URLSession!
    fileprivate var backgroundSessionCompletionHandler: (() -> Void)?
    fileprivate let TaskDescFileNameIndex = 0
    fileprivate let TaskDescFileURLIndex = 1
    fileprivate let TaskDescFileDestinationIndex = 2
    
    fileprivate weak var delegate: SabaDownloadManagerDelegate?
    
    open var downloadingArray: [SabaDownloadModel] = []
    let queue: Queuer = {
        let queue = Queuer(name: "Saba.Downloader.Queue",
                           maxConcurrentOperationCount: 1,
                           qualityOfService: .utility)
        return queue
    }()
    var queueChecker = true
    let semaphore = Semaphore()
    /// Initializer for foreground downloader only
    /// - Parameters:
    public convenience init(delegate: SabaDownloadManagerDelegate, sessionConfiguration: URLSessionConfiguration, completion: (() -> Void)? = nil) {
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
    public convenience init(session sessionIdentifer: String, delegate: SabaDownloadManagerDelegate, sessionConfiguration: URLSessionConfiguration? = nil, completion: (() -> Void)? = nil) {
        self.init()
        self.delegate = delegate
        self.sessionManager = backgroundSession(identifier: sessionIdentifer, configuration: sessionConfiguration)
        self.backgroundSessionCompletionHandler = completion
    }
    
    public class func defaultSessionConfiguration(identifier: String) -> URLSessionConfiguration {
        return URLSessionConfiguration.background(withIdentifier: identifier)
    }
    
    fileprivate func backgroundSession(identifier: String, configuration: URLSessionConfiguration? = nil) -> URLSession {
        print("-------->backgroundSession")
        let sessionConfiguration = configuration ?? SabaDownloadManager.defaultSessionConfiguration(identifier: identifier)
        assert(identifier == sessionConfiguration.identifier, "Configuration identifiers do not match")
        let session = Foundation.URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        return session
    }
}

// MARK: Private Helper functions
extension SabaDownloadManager {
    fileprivate func downloadTasks() -> [URLSessionDownloadTask] {
        var tasks: [URLSessionDownloadTask] = []
        let semaphore : DispatchSemaphore = DispatchSemaphore(value: 0)
        sessionManager.getTasksWithCompletionHandler { (dataTasks, uploadTasks, downloadTasks) -> Void in
            tasks = downloadTasks
            semaphore.signal()
        }
        
        let _ = semaphore.wait(timeout: DispatchTime.distantFuture)
        debugPrint("SabaDownloadManager: pending tasks \(tasks)")
        
        return tasks
    }
    
    fileprivate func isValidResumeData(_ resumeData: Data?) -> Bool {
        guard resumeData != nil || resumeData?.count > 0 else {
            return false
        }
        return true
    }
}

extension SabaDownloadManager: URLSessionDownloadDelegate {
    
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
        print("-------->11")
        for (index, downloadModel) in downloadingArray.enumerated() {
            if downloadTask.isEqual(downloadModel.task) {
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
        debugPrint("task id: \(task.taskIdentifier)")
        print("-------->12")
        /***** Any interrupted tasks due to any reason will be populated in failed state after init *****/
        
        DispatchQueue.main.async {
            
            let err = error as NSError?
            
            if (err?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? NSNumber)?.intValue == NSURLErrorCancelledReasonUserForceQuitApplication || (err?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? NSNumber)?.intValue == NSURLErrorCancelledReasonBackgroundUpdatesDisabled {
                
                print("-------->20")
                let downloadTask = task as! URLSessionDownloadTask
                let taskDescComponents: [String] = downloadTask.taskDescription!.components(separatedBy: ",")
                let fileName = taskDescComponents[self.TaskDescFileNameIndex]
                let fileURL = taskDescComponents[self.TaskDescFileURLIndex]
                let destinationPath = taskDescComponents[self.TaskDescFileDestinationIndex]
                
                let downloadModel = SabaDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
                if downloadModel.status != TaskStatus.paused.description() {
                    downloadModel.status = TaskStatus.failed.description()
                }
                downloadModel.task = downloadTask
                
                let resumeData = err?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                
                var newTask = downloadTask
                if self.isValidResumeData(resumeData) == true {
                    print("-------->28")
                    newTask = self.sessionManager.downloadTask(withResumeData: resumeData!)
                } else {
                    print("-------->29")
                    newTask = self.sessionManager.downloadTask(with: URL(string: fileURL as String)!)
                }
                
                newTask.taskDescription = downloadTask.taskDescription
                downloadModel.task = newTask
                
                self.downloadingArray.append(downloadModel)
                
                guard downloadModel.status != TaskStatus.paused.description() else {
                    return
                }
                
                self.delegate?.downloadRequestDidPopulatedInterruptedTasks(self.downloadingArray)
                delay(0.8) { [weak self] in
                    if !(self?.queue.operations.contains(where: { $0.isExecuting }) ?? false) && self?.queue.operationCount > 0 {
                        print("-------->urldidcomplete1-continue")
                        self?.semaphore.continue()
                    } else {
                        print("-------->executing0 > 0")
                    }
                }
                
            } else {
                for(index, object) in self.downloadingArray.enumerated() {
                    let downloadModel = object
                    if task.isEqual(downloadModel.task) {
                        if err?.code == NSURLErrorCancelled || err == nil {
                            self.downloadingArray.remove(at: index)
                            
                            if err == nil {
                                self.delegate?.downloadRequestFinished?(downloadModel, index: index)
                                delay(0.8) { [weak self] in
                                    if self?.queue.operationCount > 0 {
                                        print("-------->when download finished")
                                        print("-------->urldidcomplete22-continue")
                                        self?.semaphore.continue()
                                        self?.queue.resume()
                                    } else {
                                        print("-------->executing1 > 0")
                                    }
                                }
                            } else {
                                print("-------->23")
                                self.delegate?.downloadRequestCanceled?(downloadModel, index: index)
                                delay(0.8) { [weak self] in
                                    if !(self?.queue.operations.contains(where: { $0.isExecuting }) ?? false) &&
                                        self?.queue.operationCount > 0 {
                                        print("-------->urldidcomplete23-continue")
                                        self?.semaphore.continue()
                                    } else {
                                        print("-------->executing2 > 0")
                                    }
                                }
                            }
                            
                        } else {
                            print("-------->24")
                            let resumeData = err?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                            var newTask = task
                            if self.isValidResumeData(resumeData) == true {
                                newTask = self.sessionManager.downloadTask(withResumeData: resumeData!)
                            } else {
                                newTask = self.sessionManager.downloadTask(with: URL(string: downloadModel.fileURL)!)
                            }
                            
                            newTask.taskDescription = task.taskDescription
                            if downloadModel.status != TaskStatus.paused.description() {
                                downloadModel.status = TaskStatus.failed.description()
                            }
                            downloadModel.task = newTask as? URLSessionDownloadTask
                            
                            self.downloadingArray[index] = downloadModel
                            
                            guard downloadModel.status != TaskStatus.paused.description() else {
                                print("-------->!= TaskStatus.paused.description")
                                return
                            }
                            
                            if let error = err {
                                print("-------->25")
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel, index: index)
                            } else {
                                let error: NSError = NSError(domain: "SabaDownloadManagerDomain", code: 1000, userInfo: [NSLocalizedDescriptionKey : "Unknown error occurred"])
                                print("-------->26")
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
        print("-------->13")
        if let backgroundCompletion = self.backgroundSessionCompletionHandler {
            DispatchQueue.main.async(execute: {
                backgroundCompletion()
            })
        }
        debugPrint("All tasks are finished")
    }
}

//MARK: Public Helper Functions
extension SabaDownloadManager {
    @objc
    public func addDownloadTask(_ fileName: String,
                                request: URLRequest,
                                destinationPath: String) {
        let url = request.url!
        let fileURL = url.absoluteString
        let downloadModel = SabaDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
        downloadModel.startTime = Date()
        downloadModel.status = TaskStatus.waiting.description()
        let downloadTask = self.sessionManager.downloadTask(with: request)
        downloadTask.taskDescription = [fileName, fileURL, destinationPath].joined(separator: ",")
        downloadModel.task = downloadTask
        self.downloadingArray.append(downloadModel)
        let index = self.downloadingArray.count - 1
        self.delegate?.downloadRequestQueued?(downloadModel, index: index)
        let taskName = String(downloadModel.task?.taskIdentifier ?? 0)
        delay(1.0) { [weak self] in
            let operation = SynchronousOperation { operation in
                downloadTask.resume()
                if self?.queueChecker ?? true {
                    self?.semaphore.wait()
                }
            }
            operation.name = taskName
            if let priority = Operation.QueuePriority(rawValue: 1) {
                operation.queuePriority = priority
            }
            self?.queue.addOperation(operation)
            self?.queue.resume()
        }
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
        let downloadModel = SabaDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
        
        downloadModel.startTime = Date()
        downloadModel.status = status
        downloadModel.task = downloadTask
        
        self.downloadingArray.append(downloadModel)
        let index = self.downloadingArray.count - 1
        self.delegate?.downloadRequestDidPaused?(downloadModel, index: index)
    }
    
    @objc public func pauseDownloadTaskAtIndex(_ index: Int) {
        print("-------->pause1")
        let downloadModel = downloadingArray[index]
        
        let downloadTask = downloadModel.task
        downloadTask!.suspend()
        downloadModel.status = TaskStatus.paused.description()
        downloadModel.startTime = Date()
        
        downloadingArray[index] = downloadModel
        
        delegate?.downloadRequestDidPaused?(downloadModel, index: index)
        for oper in queue.operations {
            if let operation = oper as? SynchronousOperation,
                operation.name == String(downloadTask?.taskIdentifier ?? 0) {
                print("-------->pause1-cancel")
                operation.cancel()
                operation.finish(false)
            }
        }
        delay(0.2) { [weak self] in
            if self?.queue.operationCount > 0 {
                print("-------->pause-continue")
                self?.semaphore.continue()
//                self?.queue.resume()
            }
        }
    }
    
    @objc public func pauseWithoutContinueDownloadTasks() {
        print("-------->pause2")
        guard let index = self.downloadingArray.firstIndex(where: { $0.status ==  TaskStatus.downloading.description() }) else {
            return
        }
        
        let downloadModel = downloadingArray[index]
        guard downloadModel.status != TaskStatus.paused.description() else {
            return
        }
        
        let downloadTask = downloadModel.task
        downloadTask!.suspend()
        downloadModel.status = TaskStatus.paused.description()
        downloadModel.startTime = Date()
        
        downloadingArray[index] = downloadModel
        
        delegate?.downloadRequestDidOtherPaused?(downloadModel, index: index)
    }
    
    @objc public func resumeDownloadTaskAtIndex(_ index: Int) {
        print("-------->resume")
        let downloadModel = self.downloadingArray[index]
        let taskName = String(downloadModel.task?.taskIdentifier ?? -1)
        if let operations = queue.operations as? [SynchronousOperation],
           operations.count > 1,
           let operation = operations.first(where: { $0.name == taskName }) {
            pauseWithoutContinueDownloadTasks()
            queue.pause()
            queueChecker = false
            operation.execute()
            self.delegate?.downloadRequestDidResumed?(downloadModel, index: index)
            queueChecker = true
            queue.resume()
            print("-------->queue.resumed")
            return
        } else {
            for oper in queue.operations {
                if let operation = oper as? SynchronousOperation {
                    if operation.isExecuting {
                        operation.cancel()
                        operation.finish(false)
                    }
                }
            }
            pauseWithoutContinueDownloadTasks()
            delay(0.2) { [weak self] in
                let taskName = String(downloadModel.task?.taskIdentifier ?? 0)
                print("-------->add task ddd----> 1 --> \(taskName)")
                let operation = SynchronousOperation { operation in
                    guard downloadModel.status != TaskStatus.downloading.description() else {
                        return
                    }
                    let downloadTask = downloadModel.task
                    downloadTask!.resume()
                    downloadModel.status = TaskStatus.downloading.description()
                    
                    self?.downloadingArray[index] = downloadModel
                    self?.delegate?.downloadRequestDidResumed?(downloadModel, index: index)
                    operation.name = taskName
                    print("-------->add task ddd----> 2 --> \(taskName)")
                    self?.semaphore.wait()
                }
                operation.name = taskName
                self?.queue.addOperation(operation)
                self?.queue.resume()
            }
        }
    }
    
    @objc public func retryDownloadTaskAtIndex(_ index: Int) {
        print("-------->retry")
        let downloadModel = downloadingArray[index]
        
        guard downloadModel.status != TaskStatus.downloading.description() ||
                downloadModel.status != TaskStatus.paused.description() else {
            return
        }
        
        let downloadTask = downloadModel.task
        
        downloadTask!.resume()
        downloadModel.status = TaskStatus.downloading.description()
        downloadModel.startTime = Date()
        downloadModel.task = downloadTask
        
        downloadingArray[index] = downloadModel
    }
    
    @objc public func cancelTaskAtIndex(_ index: Int) {
        print("-------->cancel")
        let downloadInfo = downloadingArray[index]
        let downloadTask = downloadInfo.task
        downloadTask!.cancel()
        for oper in queue.operations {
            if let operation = oper as? SynchronousOperation,
                operation.name == String(downloadTask?.taskIdentifier ?? 0) {
                print("operation.name----------->\(operation.name ?? "no")")
                operation.cancel()
                if operation.isExecuting {
                    operation.finish(false)
                }
            }
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
