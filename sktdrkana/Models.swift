import Foundation
import ApplicationServices

// MARK: - Data Models

struct KeyMapping {
    var sourceModifiers: CGEventFlags
    var sourceKey: CGKeyCode
    var targetModifiers: CGEventFlags
    var targetKey: CGKeyCode
    
    static let defaultMapping = KeyMapping(
        sourceModifiers: .maskShift,
        sourceKey: 49,  // Space
        targetModifiers: .maskControl,
        targetKey: 49
    )
}

// MARK: - UserDefaults Manager

struct UserDefaultsManager {
    private static let keys = (
        sourceModifiers: "sourceModifiers",
        sourceKey: "sourceKey",
        targetModifiers: "targetModifiers",
        targetKey: "targetKey",
        reverseMouseScroll: "reverseMouseScroll"
    )
    
    static func save(mapping: KeyMapping) {
        let defaults = UserDefaults.standard
        defaults.set(Int(mapping.sourceModifiers.rawValue), forKey: keys.sourceModifiers)
        defaults.set(Int(mapping.sourceKey), forKey: keys.sourceKey)
        defaults.set(Int(mapping.targetModifiers.rawValue), forKey: keys.targetModifiers)
        defaults.set(Int(mapping.targetKey), forKey: keys.targetKey)
    }
    
    static func saveReverseMouseScroll(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: keys.reverseMouseScroll)
    }
    
    static func loadReverseMouseScroll() -> Bool {
        return UserDefaults.standard.bool(forKey: keys.reverseMouseScroll)
    }
    
    static func load() -> KeyMapping {
        let defaults = UserDefaults.standard
        
        guard defaults.object(forKey: keys.sourceKey) != nil else {
            return KeyMapping.defaultMapping
        }
        
        let sourceModifiers = CGEventFlags(rawValue: CGEventFlags.RawValue(defaults.integer(forKey: keys.sourceModifiers)))
        let sourceKey = CGKeyCode(defaults.integer(forKey: keys.sourceKey))
        let targetModifiers = CGEventFlags(rawValue: CGEventFlags.RawValue(defaults.integer(forKey: keys.targetModifiers)))
        let targetKey = CGKeyCode(defaults.integer(forKey: keys.targetKey))
        
        return KeyMapping(
            sourceModifiers: sourceModifiers,
            sourceKey: sourceKey,
            targetModifiers: targetModifiers,
            targetKey: targetKey
        )
    }
}

// MARK: - KeyCode Utilities

struct KeyCodeMapper {
    static func modifierName(_ modifiers: CGEventFlags) -> String {
        var names: [String] = []
        if modifiers.contains(.maskShift) { names.append("Shift") }
        if modifiers.contains(.maskControl) { names.append("Control") }
        if modifiers.contains(.maskCommand) { names.append("Command") }
        if modifiers.contains(.maskAlternate) { names.append("Option") }
        return names.isEmpty ? "なし" : names.joined(separator: "+")
    }
    
    static func keyName(_ keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        case 53: return "Escape"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        default: return "キーコード \(keyCode)"
        }
    }
    
    static func modifierIndex(_ modifiers: CGEventFlags) -> Int {
        if modifiers.contains(.maskShift) { return 0 }
        if modifiers.contains(.maskControl) { return 1 }
        if modifiers.contains(.maskCommand) { return 2 }
        if modifiers.contains(.maskAlternate) { return 3 }
        return 0
    }
    
    static func keyIndex(_ keyCode: CGKeyCode) -> Int {
        switch keyCode {
        case 49: return 0  // Space
        case 36: return 1  // Return
        case 0: return 2   // A
        case 11: return 3  // B
        case 8: return 4   // C
        default: return 0
        }
    }
    
    static func modifierFlagFromName(_ name: String) -> CGEventFlags {
        switch name {
        case "Shift": return .maskShift
        case "Control": return .maskControl
        case "Command": return .maskCommand
        case "Option": return .maskAlternate
        default: return []
        }
    }
    
    static func keyCodeFromName(_ name: String) -> CGKeyCode {
        switch name {
        case "Space": return 49
        case "Return": return 36
        case "A": return 0
        case "B": return 11
        case "C": return 8
        default: return 49
        }
    }
}
