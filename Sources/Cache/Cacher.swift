//
//  Cacher.swift
//  Cacher
//
//  Created by Aashish Tamsya on 24/06/19.
//  Copyright © 2019 Aashish Tamsya. All rights reserved.
//

import Foundation

private var taskPool: [URLSessionDataTask: URL] = [:]

public class Cacher {
  public static let sharedCache = Cacher()
  
  private let memoryCache = MemoryCache()
  private let diskCache = DiskCache()
  private var session: URLSession
  
  init() {
    session = URLSession(configuration: .default)
  }
}

extension Cacher: Cache {
  public func store<T>(to: CacheType, key: String, object: T, _ completion: (() -> Void)?) where T: Cachable {
    switch to {
    case .disk:
      diskCache.store(key: key, object: object, completion)
    case .memory:
      memoryCache.store(key: key, object: object, completion)
    case .none:
      completion?()
    }
  }
  
  public func retrieve<T>(from: CacheType, key: String, _ completion: @escaping (T?) -> Void) where T: Cachable {
    switch from {
    case .disk:
      diskCache.retrieve(key: key) { (object: T?) in
        if let object = object {
          completion(object)
          return
        } else {
          completion(nil)
          return
        }
      }

    case .memory:
      memoryCache.retrieve(key: key) { (object: T?) in
        if let object = object {
          completion(object)
          return
        } else {
          completion(nil)
          return
        }
      }
    case .none:
      completion(nil)
    }
  }
  
  public func removeAll() {
    memoryCache.removeAll()
  }
}

extension Cacher: Download {
  public func download<T>(cacheType type: CacheType, url: URL, completion: @escaping (T?, CacheType) -> Void) -> RequestToken? where T: Cachable {
    guard let key = url.key else {
      completion(nil, .none)
      return nil
    }
    var token: RequestToken?
    switch type {
    case .none:
      return nil
    case .disk:
      diskCache.retrieve(key: key) { (object: Data?) in
        if let data = object {
          completion(data as? T, .disk)
        } else {
          let task = self.session.dataTask(with: url) { [weak self] data, _, _ in
            guard let strongSelf = self, let data = data else {
              completion(nil, .none)
              return
            }
            strongSelf.memoryCache.store(key: url.absoluteString, object: data) {
              completion(data as? T, .none)
            }
          }
          task.resume()
          let requestToken = RequestToken(task)
          taskPool[task] = url
          token = requestToken
        }
      }
    case .memory:
      memoryCache.retrieve(key: key) { (object: Data?) in
        if let data = object {
          completion(data as? T, .memory)
        } else {
          let task = self.session.dataTask(with: url) { [weak self] data, _, _ in
            guard let strongSelf = self, let data = data else {
              completion(nil, .none)
              return
            }
            strongSelf.memoryCache.store(key: url.absoluteString, object: data) {
              completion(data as? T, .none)
            }
          }
          task.resume()
          let requestToken = RequestToken(task)
          taskPool[task] = url
          token = requestToken
        }
      }
    }
    return token
  }
  
//  public func download<T>(url: URL, completion: @escaping (T?, CacheType) -> Void) -> RequestToken? where T: Cachable {
//
//
//  }
  
  public func cancel(_ url: URL, token: RequestToken? = nil) -> Bool {
    guard let task = token?.task, let cancelToken = taskPool.filter({ $0.key == task && $0.value == url }).first?.key else { return false }
    cancelToken.cancel()
    taskPool.removeValue(forKey: cancelToken)
    return true
  }
}
