//
//  File.swift
//  
//
import Foundation
public protocol SabaDownloadManagerProtocol {
    var downloadingArray: [SabaDownloadModel] { get set }
    init(delegate: SabaDownloadManagerDelegate,
         sessionConfiguration: URLSessionConfiguration,
         completion: (() -> Void)?)
    init(session sessionIdentifer: String,
         delegate: SabaDownloadManagerDelegate,
         sessionConfiguration: URLSessionConfiguration?,
         completion: (() -> Void)?)
    func addDownloadTask(_ fileName: String,
                                request: URLRequest,
                                destinationPath: String)
    func addDownloadArray(_ fileName: String,
                                request: URLRequest,
                                destinationPath: String,
                                status: String)
    func pauseDownloadTaskAtIndex(_ index: Int)
    func resumeDownloadTaskAtIndex(_ index: Int)
    func retryDownloadTaskAtIndex(_ index: Int)
    func cancelTaskAtIndex(_ index: Int)
    func presentNotificationForDownload(_ notifAction: String, notifBody: String)
}
