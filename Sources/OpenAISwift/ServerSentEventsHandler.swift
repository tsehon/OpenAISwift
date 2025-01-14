//
//  ServerSentEventsHandler.swift
//  
//
//  Created by Vic on 2023-03-25.
//

import Foundation
#if canImport(FoundationNetworking) && canImport(FoundationXML)
import FoundationNetworking
import FoundationXML
#endif

class ServerSentEventsHandler: NSObject {
    
    var onEventReceived: ((Result<OpenAI<StreamMessageResult>, OpenAIError>) -> Void)?
    var onComplete: (() -> Void)?
    
    private var session: URLSession?
    private var task: URLSessionDataTask?
       
    func connect(with request: URLRequest) {
        /**
         The `URLSessionConfiguration.default` property returns the default session configuration object.
         
         The default session configuration uses the global singleton credential, cache, and cookie storage objects. It also uses the default `URLCache` object, which is a memory-only cache with no disk storage.
         
         You can use this configuration object as a starting point and customize it further to meet your specific needs.
         
         - Note: This property is defined in the `URLSessionConfiguration` class.
         */
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session?.dataTask(with: request)
        task?.resume()
    }
    
    func disconnect() {
        task?.cancel()
    }

    func processEvent(_ eventData: Data) {
        do {
            let res = try JSONDecoder().decode(OpenAI<StreamMessageResult>.self, from: eventData)
            onEventReceived?(.success(res))
        } catch {
            onEventReceived?(.failure(.decodingError(error: error)))
        }
    }
}

extension ServerSentEventsHandler: URLSessionDataDelegate {
    
    /// It will be called several times, each time could return one chunk of data or multiple chunk of data
    /// The JSON look liks this:
    /// `data: {"id":"chatcmpl-6yVTvD6UAXsE9uG2SmW4Tc2iuFnnT","object":"chat.completion.chunk","created":1679878715,"model":"gpt-3.5-turbo-0301","choices":[{"delta":{"role":"assistant"},"index":0,"finish_reason":null}]}`
    /// `data: {"id":"chatcmpl-6yVTvD6UAXsE9uG2SmW4Tc2iuFnnT","object":"chat.completion.chunk","created":1679878715,"model":"gpt-3.5-turbo-0301","choices":[{"delta":{"content":"Once"},"index":0,"finish_reason":null}]}`
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let eventString = String(data: data, encoding: .utf8) {
            let lines = eventString.split(separator: "\n")
            for line in lines {
                if line.hasPrefix("data:") && line != "data: [DONE]" {
                    if let eventData = String(line.dropFirst(5)).data(using: .utf8) {
                        processEvent(eventData)
                    } else {
                        disconnect()
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onEventReceived?(.failure(.genericError(error: error)))
        } else {
            onComplete?()
        }
    }
}
