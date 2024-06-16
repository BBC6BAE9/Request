//
//  ApiRequest.swift
//  BilibiliLive
//
//  Created by yicheng on 2021/4/25.
//

import Alamofire
import CryptoKit
import Foundation
import SwiftyJSON

struct LoginToken: Codable {
    let mid: Int
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    var expireDate: Date?
}

enum ApiRequest {
    static let appkey = "5ae412b53418aac5"
    static let appsec = "5b9cf6c9786efd204dcf0c1ce2d08436"
    
    enum EndPoint {
        
        static let loginQR = "https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code"
        static let verifyQR = "https://passport.bilibili.com/x/passport-tv-login/qrcode/poll"
        static let refresh = "https://passport.bilibili.com/api/v2/oauth2/refresh_token"
        static let ssoCookie = "https://passport.bilibili.com/api/login/sso"
        static let feed = "https://app.bilibili.com/x/v2/feed/index"
        static let season = "https://api.bilibili.com/pgc/view/v2/app/season"
    }
    
    enum LoginState {
        case success(token: LoginToken)
        case fail
        case expire
        case waiting
    }
    
    static func save(token: LoginToken) {
        UserDefaults.standard.set(token, forKey: "token")
    }
    
    static func getToken() -> LoginToken? {
        if let token: LoginToken = UserDefaults.standard.codable(forKey: "token") {
            return token
        }
        return nil
    }
    
    static func isLogin() -> Bool {
        return getToken() != nil
    }
    
    static func sign(for param: [String: Any]) -> [String: Any] {
        var newParam = param
        newParam["appkey"] = appkey
        newParam["ts"] = "\(Int(Date().timeIntervalSince1970))"
        newParam["local_id"] = "0"
        newParam["mobi_app"] = "iphone"
        newParam["device"] = "pad"
        newParam["device_name"] = "iPad"
        var rawParam = newParam
            .sorted(by: { $0.0 < $1.0 })
            .map({ "\($0.key)=\($0.value)" })
            .joined(separator: "&")
        rawParam.append(appsec)
        
        let md5 = Insecure.MD5
            .hash(data: rawParam.data(using: .utf8)!)
            .map { String(format: "%02hhx", $0) }
            .joined()
        newParam["sign"] = md5
        return newParam
    }
    
    static func logout(complete: (() -> Void)? = nil) {
        UserDefaults.standard.removeObject(forKey: "token")
        complete?()
    }
    
    static func requestJSON(_ url: URLConvertible,
                            method: HTTPMethod = .get,
                            parameters: Parameters = [:],
                            auth: Bool = true,
                            encoding: ParameterEncoding = URLEncoding.default,
                            complete: ((Result<JSON, RequestError>) -> Void)? = nil)
    {
        var parameters = parameters
        if auth {
            parameters["access_key"] = getToken()?.accessToken
        }
        parameters = sign(for: parameters)
        AF.request(url, method: method, parameters: parameters, encoding: encoding).responseData { response in
            switch response.result {
            case let .success(data):
                let json = JSON(data)
                print(json)
                let errorCode = json["code"].intValue
                if errorCode != 0 {
                    if errorCode == -101 {
                        UserDefaults.standard.removeObject(forKey: "token")
                        // TODO: 显示登录窗口
                        //                        AppDelegate.shared.showLogin()
                    }
                    let message = json["message"].stringValue
                    print(errorCode, message)
                    complete?(.failure(.statusFail(code: errorCode, message: message)))
                    return
                }
                complete?(.success(json))
            case let .failure(err):
                print(err)
                complete?(.failure(.networkFail))
            }
        }
    }
    
    static func request<T: Decodable>(_ url: URLConvertible,
                                      method: HTTPMethod = .get,
                                      parameters: Parameters = [:],
                                      auth: Bool = true,
                                      encoding: ParameterEncoding = URLEncoding.default,
                                      decoder: JSONDecoder = JSONDecoder(),
                                      complete: ((Result<T, RequestError>) -> Void)?)
    {
        requestJSON(url, method: method, parameters: parameters, auth: auth, encoding: encoding) { result in
            switch result {
            case let .success(data):
                do {
                    let data = try data["data"].rawData()
                    let object = try decoder.decode(T.self, from: data)
                    complete?(.success(object))
                } catch let err {
                    print(err)
                    complete?(.failure(.decodeFail(message: err.localizedDescription + String(describing: err))))
                }
            case let .failure(err):
                complete?(.failure(err))
            }
        }
    }
    
    static func request<T: Decodable>(_ url: URLConvertible,
                                      method: HTTPMethod = .get,
                                      parameters: Parameters = [:],
                                      auth: Bool = true,
                                      encoding: ParameterEncoding = URLEncoding.default,
                                      decoder: JSONDecoder = JSONDecoder()) async throws -> T
    {
        try await withCheckedThrowingContinuation { configure in
            request(url, method: method, parameters: parameters, auth: auth, encoding: encoding, decoder: decoder) { resp in
                configure.resume(with: resp)
            }
        }
    }
    
    static func requestLoginQR(handler: ((String, String) -> Void)? = nil) {
        class Resp: Codable {
            let authCode: String
            let url: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        request(EndPoint.loginQR, method: .post, auth: false, decoder: decoder) {
            (result: Result<Resp, RequestError>) in
            switch result {
            case let .success(res):
                handler?(res.authCode, res.url)
            case let .failure(error):
                print(error)
            }
        }
    }
    
    struct LoginResp: Codable {
        struct CookieInfo: Codable {
            let domains: [String]
            let cookies: [Cookie]
            func toCookies() -> [HTTPCookie] {
                domains.map { domain in
                    cookies.compactMap { $0.toCookie(domain: domain) }
                }.reduce([], +)
            }
        }
        
        struct Cookie: Codable {
            let name: String
            let value: String
            let httpOnly: Int
            let expires: Int
            
            func toCookie(domain: String) -> HTTPCookie? {
                HTTPCookie(properties: [.domain: domain,
                                        .name: name,
                                        .value: value,
                                        .expires: Date(timeIntervalSince1970: TimeInterval(expires)),
                                        HTTPCookiePropertyKey("HttpOnly"): httpOnly,
                                        .path: ""])
            }
        }
        
        var tokenInfo: LoginToken
        let cookieInfo: CookieInfo
    }
    
    /// 在后台存储的供给AppStore审核的账号的token
    struct LoginRespStore:Codable {
        let id:Int
        let content:String
    }
    
    static func verifyLoginAppStore(handler: ((LoginState) -> Void)? = nil) {
        var request = URLRequest(url: URL(string: "http://146.56.219.95:8080/api/loginresps/1")!,timeoutInterval: Double.infinity)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                print(String(describing: error))
                return
            }
            
            let decoder = JSONDecoder()
            
            do {
                let loginRespStore = try decoder.decode(LoginRespStore.self, from: data)
                
                guard let data = loginRespStore.content.data(using: .utf8),
                   let dic = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]  else{
                    return
                }
                
                let jsonData = try JSONSerialization.data(withJSONObject: dic, options: .prettyPrinted)
                var res = try decoder.decode(ApiRequest.LoginResp.self, from: jsonData)
                res.tokenInfo.expireDate = Date().addingTimeInterval(TimeInterval(res.tokenInfo.expiresIn))
                CookieHandler.shared.saveCookie(list: res.cookieInfo.toCookies())
                handler?(.success(token: res.tokenInfo))
            } catch {
                print("Error:", error)
            }
        }
        
        task.resume()
    }
}

private extension UserDefaults {
    func codable<Element: Codable>(forKey key: String) -> Element? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let element = try? JSONDecoder().decode(Element.self, from: data)
        return element
    }
}
