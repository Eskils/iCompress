//
//  ValueManager.swift
//  Dataforbruk
//
//  Created by Eskil Sviggum on 01/02/2022.
//
import Foundation

class ValueManager<T> {
    typealias ValueHandler = (T)->Void
    
    var value: T? {
        didSet {
            DispatchQueue.main.async { [self] in
                if let value = value { listeners.forEach { $0.value(value) } }
            }
        }
    }
    
    private var listeners = [String: ValueHandler]()
    
    
    func listenToUpdates(_ handler: @escaping ValueHandler) -> String {
        let key = UUID().uuidString
        listeners[key] = handler
        if let value = value { handler(value) }
        return key
    }
    
    func unlistenToUpdates(withKey key: String) {
        if (listeners[key] != nil) { listeners.removeValue(forKey: key) }
    }
    
}
