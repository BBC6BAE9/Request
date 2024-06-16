//
//  WebRequest.swift
//  BilibiliLive
//
//  Created by yicheng on 2021/4/29.
//

import Alamofire
import Foundation
import SwiftProtobuf
import SwiftyJSON
import os

var logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "unknow bundle id", category: "WebRequest")

public enum RequestError: LocalizedError {
    case networkFail
    case statusFail(code: Int, message: String)
    case decodeFail(message: String)
    
    public var errorDescription: String? {
        switch self {
               case .networkFail:
                   return "网络请求失败"
               case .statusFail(let code, let message):
                    return message
               case .decodeFail(let message):
                   return "Decoding failed: \(message)"
               }
    }
}

public extension Error {
    public var code:Int? {
        if let error = self as? RequestError {
            if case RequestError.statusFail(let code, _) = error {
                return code
            }else{
                return (self as NSError).code
            }
        }else {
            return (self as NSError).code
        }
    }
}

enum ValidationError: Error {
    case argumentInvalid(message: String)
}

enum NoCookieSession {
    static let session = Session(configuration: URLSessionConfiguration.ephemeral)
}

public enum WebRequest {

    public static func requestData(method: HTTPMethod = .get,
                            url: URLConvertible,
                            parameters: Parameters = [:],
                            headers: [String: String]? = nil,
                            noCookie: Bool = false,
                            complete: ((Result<Data, RequestError>) -> Void)? = nil)
    {
        var parameters = parameters
        if method != .get {
            parameters["biliCSRF"] = CookieHandler.shared.csrf()
            parameters["csrf"] = CookieHandler.shared.csrf()
        }
        
        var afheaders = HTTPHeaders()
        if let headers {
            for (k, v) in headers {
                afheaders.add(HTTPHeader(name: k, value: v))
            }
        }
        
        if !afheaders.contains(where: { $0.name == "User-Agent" }) {
            afheaders.add(.userAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"))
        }
        
        if !afheaders.contains(where: { $0.name == "User-Agent" }) {
            afheaders.add(.userAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"))
        }
        
        if !afheaders.contains(where: { $0.name == "Referer" }) {
            afheaders.add(HTTPHeader(name: "Referer", value: "https://www.bilibili.com"))
        }
        
        var session = Session.default
        if noCookie {
            session = NoCookieSession.session
            session.sessionConfiguration.httpShouldSetCookies = false
        }
        session.sessionConfiguration.timeoutIntervalForResource = 10
        session.sessionConfiguration.timeoutIntervalForRequest = 10
        session.request(url,
                        method: method,
                        parameters: parameters,
                        encoding: URLEncoding.default,
                        headers: afheaders,
                        interceptor: nil)
        .responseData { response in
            switch response.result {
            case let .success(data):
                complete?(.success(data))
            case let .failure(err):
                print(err)
                complete?(.failure(.networkFail))
            }
        }
    }
    
    public static func requestJSON(method: HTTPMethod = .get,
                            url: URLConvertible,
                            parameters: Parameters = [:],
                            headers: [String: String]? = nil,
                            dataObj: String = "data",
                            noCookie: Bool = false,
                            complete: ((Result<JSON, RequestError>) -> Void)? = nil)
    {
        requestData(method: method, url: url, parameters: parameters, headers: headers, noCookie: noCookie) { response in
            switch response {
            case let .success(data):
                let json = JSON(data)
                let errorCode = json["code"].intValue
                if errorCode != 0 {
                    let message = json["message"].stringValue
                    print(errorCode, message)
                    complete?(.failure(.statusFail(code: errorCode, message: message)))
                    return
                }
                let dataj = json[dataObj]
                print("\(url) response: \(json)")
                complete?(.success(dataj))
            case let .failure(err):
                complete?(.failure(err))
            }
        }
    }
    
    public static func request<T: Decodable>(method: HTTPMethod = .get,
                                      url: URLConvertible,
                                      parameters: Parameters = [:],
                                      headers: [String: String]? = nil,
                                      decoder: JSONDecoder? = nil,
                                      dataObj: String = "data",
                                      noCookie: Bool = false,
                                      complete: ((Result<T, RequestError>) -> Void)?)
    {
        requestJSON(method: method, url: url, parameters: parameters, headers: headers, dataObj: dataObj, noCookie: noCookie) { response in
            switch response {
            case let .success(data):
                do {
                    let data = try data.rawData()
                    let object = try (decoder ?? JSONDecoder()).decode(T.self, from: data)
                    complete?(.success(object))
                } catch let err {
                    print("decode fail:", err)
                    complete?(.failure(.decodeFail(message: err.localizedDescription + String(describing: err))))
                }
            case let .failure(err):
                complete?(.failure(err))
            }
        }
    }
    
    public static func requestIndex() {
        requestData(url: "https://www.bilibili.com", complete: {
            _ in
            CookieHandler.shared.backupCookies()
        })
    }
    
    public static func requestPB<T: SwiftProtobuf.Message>(method: HTTPMethod = .get,
                                                    url: URLConvertible,
                                                    parameters: Parameters = [:],
                                                    headers: [String: String]? = nil,
                                                    noCookie: Bool = false,
                                                    complete: ((Result<T, RequestError>) -> Void)? = nil)
    {
        requestData(method: method, url: url, parameters: parameters, headers: headers, noCookie: noCookie) { response in
            switch response {
            case let .success(data):
                do {
                    let protobufObject = try T(serializedData: data)
                    complete?(.success(protobufObject))
                } catch let err {
                    logger.notice("Protobuf parsing error: \(err.localizedDescription)")
                    complete?(.failure(.decodeFail(message: "probobuf decode error: \(err)")))
                }
            case let .failure(err):
                complete?(.failure(err))
            }
        }
    }
    
    public static func requestJSON(method: HTTPMethod = .get,
                            url: URLConvertible,
                            parameters: Parameters = [:],
                            headers: [String: String]? = nil) async throws -> JSON
    {
        return try await withCheckedThrowingContinuation { configure in
            requestJSON(method: method, url: url, parameters: parameters, headers: headers) { resp in
                configure.resume(with: resp)
            }
        }
    }
    
    public static func request<T: Decodable>(method: HTTPMethod = .get,
                                      url: URLConvertible,
                                      parameters: Parameters = [:],
                                      headers: [String: String]? = nil,
                                      decoder: JSONDecoder? = nil,
                                      noCookie: Bool = false,
                                      dataObj: String = "data") async throws -> T
    {
        return try await withCheckedThrowingContinuation { configure in
            request(method: method, url: url, parameters: parameters, headers: headers, decoder: decoder, dataObj: dataObj, noCookie: noCookie) {
                (res: Result<T, RequestError>) in
                switch res {
                case let .success(content):
                    configure.resume(returning: content)
                case let .failure(err):
                    configure.resume(throwing: err)
                }
            }
        }
    }
    
    public static func requestPB<T: SwiftProtobuf.Message>(method: HTTPMethod = .get,
                                                    url: URLConvertible,
                                                    parameters: Parameters = [:],
                                                    headers: [String: String]? = nil,
                                                    noCookie: Bool = false,
                                                    dataObj _: String = "data") async throws -> T
    {
        return try await withCheckedThrowingContinuation { configure in
            requestPB(method: method, url: url, parameters: parameters, headers: headers, noCookie: noCookie) {
                (res: Result<T, RequestError>) in
                switch res {
                case let .success(content):
                    configure.resume(returning: content)
                case let .failure(err):
                    configure.resume(throwing: err)
                }
            }
        }
    }
}
