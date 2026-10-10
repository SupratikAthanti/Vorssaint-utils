// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One private, credential-free session per request. The delegate queues are
/// serial; response bytes are rejected before they enter the retained buffer.
final class BoundedHTTPClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let completion: (Result<(Data, URLResponse), Error>) -> Void
    private var data = Data()
    private var response: URLResponse?
    private var rejection: Error?

    init(limit: Int, completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        self.limit = max(0, limit)
        self.completion = completion
    }

    static func load(_ request: URLRequest, maxBytes: Int,
                     upload: Data? = nil, file: URL? = nil,
                     requestTimeout: TimeInterval = 75, resourceTimeout: TimeInterval = 90,
                     completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        let delegate = BoundedHTTPClient(limit: maxBytes, completion: completion)
        let config = URLSessionConfiguration.ephemeral
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task: URLSessionTask
        if let upload { task = session.uploadTask(with: request, from: upload) }
        else if let file { task = session.uploadTask(with: request, fromFile: file) }
        else { task = session.dataTask(with: request) }
        task.resume()
        session.finishTasksAndInvalidate()
    }

    static func load(_ request: URLRequest, maxBytes: Int,
                     upload: Data? = nil, file: URL? = nil,
                     requestTimeout: TimeInterval = 75, resourceTimeout: TimeInterval = 90) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            load(request, maxBytes: maxBytes, upload: upload, file: file,
                 requestTimeout: requestTimeout, resourceTimeout: resourceTimeout) {
                continuation.resume(with: $0)
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard response.expectedContentLength <= Int64(limit) else {
            rejection = URLError(.dataLengthExceedsMaximum)
            completionHandler(.cancel)
            return
        }
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= limit - data.count else {
            rejection = URLError(.dataLengthExceedsMaximum)
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward deletion credentials, uploaded content or feedback
        // to a destination chosen by a redirect response.
        rejection = URLError(.httpTooManyRedirects)
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = rejection ?? error { completion(.failure(error)) }
        else if let response { completion(.success((data, response))) }
        else { completion(.failure(URLError(.badServerResponse))) }
    }
}
