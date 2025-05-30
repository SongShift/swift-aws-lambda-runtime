//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOCore
import NIOHTTP1

/// An HTTP based client for AWS Runtime Engine. This encapsulates the RESTful methods exposed by the Runtime Engine:
/// * /runtime/invocation/next
/// * /runtime/invocation/response
/// * /runtime/invocation/error
/// * /runtime/init/error
struct LambdaRuntimeClient {
    private let eventLoop: EventLoop
    private let allocator = ByteBufferAllocator()
    private let httpClient: HTTPClient

    init(eventLoop: EventLoop, configuration: LambdaConfiguration.RuntimeEngine) {
        self.eventLoop = eventLoop
        self.httpClient = HTTPClient(eventLoop: eventLoop, configuration: configuration)
    }

    /// Requests invocation from the control plane.
    func getNextInvocation(logger: Logger) -> EventLoopFuture<(Invocation, ByteBuffer)> {
        let url = Consts.invocationURLPrefix + Consts.getNextInvocationURLSuffix
        logger.debug("requesting work from lambda runtime engine using \(url)")
        return self.httpClient.get(url: url, headers: LambdaRuntimeClient.defaultHeaders).flatMapThrowing { response in
            guard response.status == .ok else {
                throw LambdaRuntimeError.badStatusCode(response.status)
            }
            let invocation = try Invocation(headers: response.headers)
            guard let event = response.body else {
                throw LambdaRuntimeError.noBody
            }
            return (invocation, event)
        }.flatMapErrorThrowing { error in
            switch error {
            case HTTPClient.Errors.timeout:
                throw LambdaRuntimeError.upstreamError("timeout")
            case HTTPClient.Errors.connectionResetByPeer:
                throw LambdaRuntimeError.upstreamError("connectionResetByPeer")
            default:
                throw error
            }
        }
    }

    /// Reports a result to the Runtime Engine.
    func reportResults(logger: Logger, invocation: Invocation, result: Result<ByteBuffer?, Error>) -> EventLoopFuture<Void> {
        var url = Consts.invocationURLPrefix + "/" + invocation.requestID
        var body: ByteBuffer?
        let headers: HTTPHeaders

        switch result {
        case .success(let buffer):
            url += Consts.postResponseURLSuffix
            body = buffer
            headers = LambdaRuntimeClient.defaultHeaders
        case .failure(let error):
            url += Consts.postErrorURLSuffix
            
            /*
             If a LambdaError is thrown, we allow a custom errorType to be thrown from the function
             */
            var errorResponse: ErrorResponse
            if let lambdaError = error as? LambdaError {
                errorResponse = ErrorResponse(errorType: lambdaError.errorType, errorMessage: lambdaError.errorMessage)
            } else {
                errorResponse = ErrorResponse(errorType: Consts.functionError, errorMessage: "\(error)")
            }
            
            let bytes = errorResponse.toJSONBytes()
            body = self.allocator.buffer(capacity: bytes.count)
            body!.writeBytes(bytes)
            headers = LambdaRuntimeClient.errorHeaders
        }
        logger.debug("reporting results to lambda runtime engine using \(url)")
        return self.httpClient.post(url: url, headers: headers, body: body).flatMapThrowing { response in
            guard response.status == .accepted else {
                throw LambdaRuntimeError.badStatusCode(response.status)
            }
            return ()
        }.flatMapErrorThrowing { error in
            switch error {
            case HTTPClient.Errors.timeout:
                throw LambdaRuntimeError.upstreamError("timeout")
            case HTTPClient.Errors.connectionResetByPeer:
                throw LambdaRuntimeError.upstreamError("connectionResetByPeer")
            default:
                throw error
            }
        }
    }

    /// Reports an initialization error to the Runtime Engine.
    func reportInitializationError(logger: Logger, error: Error) -> EventLoopFuture<Void> {
        let url = Consts.postInitErrorURL
        let errorResponse = ErrorResponse(errorType: Consts.initializationError, errorMessage: "\(error)")
        let bytes = errorResponse.toJSONBytes()
        var body = self.allocator.buffer(capacity: bytes.count)
        body.writeBytes(bytes)
        logger.warning("reporting initialization error to lambda runtime engine using \(url)")
        return self.httpClient.post(url: url, headers: LambdaRuntimeClient.errorHeaders, body: body).flatMapThrowing { response in
            guard response.status == .accepted else {
                throw LambdaRuntimeError.badStatusCode(response.status)
            }
            return ()
        }.flatMapErrorThrowing { error in
            switch error {
            case HTTPClient.Errors.timeout:
                throw LambdaRuntimeError.upstreamError("timeout")
            case HTTPClient.Errors.connectionResetByPeer:
                throw LambdaRuntimeError.upstreamError("connectionResetByPeer")
            default:
                throw error
            }
        }
    }

    /// Cancels the current request, if one is running. Only needed for debugging purposes
    func cancel() {
        self.httpClient.cancel()
    }
}

enum LambdaRuntimeError: Error {
    case badStatusCode(HTTPResponseStatus)
    case upstreamError(String)
    case invocationMissingHeader(String)
    case noBody
    case json(Error)
    case shutdownError(shutdownError: Error, runnerResult: Result<Int, Error>)
}

extension LambdaRuntimeClient {
    static let defaultHeaders = HTTPHeaders([("user-agent", "Swift-Lambda/Unknown")])

    /// These headers must be sent along an invocation or initialization error report
    static let errorHeaders = HTTPHeaders([
        ("user-agent", "Swift-Lambda/Unknown"),
        ("lambda-runtime-function-error-type", "Unhandled"),
    ])
}
