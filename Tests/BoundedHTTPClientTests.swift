// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum BoundedHTTPClientTests {
    static func run(_ suite: TestSuite) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://example.invalid/fixture")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
        var result: Result<(Data, URLResponse), Error>?
        let client = BoundedHTTPClient(limit: 4) { result = $0 }
        let task = session.dataTask(with: url)
        client.urlSession(session, dataTask: task, didReceive: response) {
            suite.expect($0 == .allow, "unknown-length response is streamed")
        }
        client.urlSession(session, dataTask: task, didReceive: Data([1, 2, 3]))
        client.urlSession(session, dataTask: task, didReceive: Data([4, 5]))
        client.urlSession(session, task: task, didCompleteWithError: nil)
        if case .failure = result { suite.expect(true, "oversized chunk fails before retention") }
        else { suite.expect(false, "oversized chunk fails before retention") }
        let redirect = BoundedHTTPClient(limit: 4) { result = $0 }
        redirect.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: url)) {
            suite.expect($0 == nil, "sensitive requests refuse redirects")
        }
        redirect.urlSession(session, task: task, didCompleteWithError: nil)
        if case .failure = result { suite.expect(true, "redirect refusal is surfaced as failure") }
        else { suite.expect(false, "redirect refusal is surfaced as failure") }
    }
}
