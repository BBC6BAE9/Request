//
//  LoginViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/3/28.
//

import Foundation

public class CookieHandler {
    
    public static let shared: CookieHandler = .init()

    let defaults = UserDefaults.standard
    let cookieStorage = HTTPCookieStorage.shared

    public func getCookie(forURL url: String) -> [HTTPCookie] {
        let computedUrl = URL(string: url)
        let cookies = cookieStorage.cookies(for: computedUrl!) ?? []

        return cookies
    }

    public func backupCookies() {
        var cookieDict = [String: AnyObject]()
        for cookie in cookieStorage.cookies ?? [] {
            cookieDict[cookie.name] = cookie.properties as AnyObject?
        }

        defaults.set(cookieDict, forKey: "SavedCookie")
    }

    public func removeCookie() {
        defaults.removeObject(forKey: "SavedCookie")
    }

    public func restoreCookies() {
        if let cookieDictionary = defaults.dictionary(forKey: "SavedCookie") {
            for (_, cookieProperties) in cookieDictionary {
                if let cookie = HTTPCookie(properties: cookieProperties as! [HTTPCookiePropertyKey: Any]) {
                    cookieStorage.setCookie(cookie)
                }
            }
        }
    }

    public func saveCookie(list: [HTTPCookie]) {
        list.forEach({ cookieStorage.setCookie($0) })
        backupCookies()
    }

    public func csrf() -> String? {
        let cookies = getCookie(forURL: "https://bilibili.com")
        return cookies.first(where: { $0.name == "bili_jct" })?.value
    }

    public func buvid3() -> String {
        let cookies = getCookie(forURL: "https://bilibili.com")
        return cookies.first(where: { $0.name == "buvid3" })?.value ?? ""
    }
}
