import Foundation
import ApplicationServices

// MARK: - Data Models

struct KeyMapping {
    var sourceModifiers: CGEventFlags
    var sourceKey: CGKeyCode
    var targetModifiers: CGEventFlags
    var targetKey: CGKeyCode
    var id: UUID
    var enabled: Bool
    
    init(sourceModifiers: CGEventFlags, sourceKey: CGKeyCode, targetModifiers: CGEventFlags, targetKey: CGKeyCode, id: UUID = UUID(), enabled: Bool = true) {
        self.sourceModifiers = sourceModifiers
        self.sourceKey = sourceKey
        self.targetModifiers = targetModifiers
        self.targetKey = targetKey
        self.id = id
        self.enabled = enabled
    }
    
    static let defaultMapping = KeyMapping(
        sourceModifiers: .maskShift,
        sourceKey: 49,  // Space
        targetModifiers: .maskControl,
        targetKey: 49,
        enabled: false  // デフォルトは無効
    )
}

// MARK: - UserDefaults Manager

struct UserDefaultsManager {
    private static let mappingsKey = "keyMappings"
    private static let reverseMouseScrollKey = "reverseMouseScroll"
    
    static func save(mappings: [KeyMapping]) {
        let defaults = UserDefaults.standard
        let data = mappings.map { mapping -> [String: Any] in
            [
                "id": mapping.id.uuidString,
                "sourceModifiers": Int(mapping.sourceModifiers.rawValue),
                "sourceKey": Int(mapping.sourceKey),
                "targetModifiers": Int(mapping.targetModifiers.rawValue),
                "targetKey": Int(mapping.targetKey),
                "enabled": mapping.enabled
            ]
        }
        defaults.set(data, forKey: mappingsKey)
    }
    
    static func saveReverseMouseScroll(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: reverseMouseScrollKey)
    }
    
    static func loadReverseMouseScroll() -> Bool {
        return UserDefaults.standard.bool(forKey: reverseMouseScrollKey)
    }
    
    static func load() -> [KeyMapping] {
        let defaults = UserDefaults.standard
        
        guard let data = defaults.array(forKey: mappingsKey) as? [[String: Any]] else {
            return [KeyMapping.defaultMapping]
        }
        
        return data.compactMap { dict -> KeyMapping? in
            guard let idString = dict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let sourceModifiers = dict["sourceModifiers"] as? Int,
                  let sourceKey = dict["sourceKey"] as? Int,
                  let targetModifiers = dict["targetModifiers"] as? Int,
                  let targetKey = dict["targetKey"] as? Int else {
                return nil
            }
            
            let enabled = dict["enabled"] as? Bool ?? true
            
            return KeyMapping(
                sourceModifiers: CGEventFlags(rawValue: CGEventFlags.RawValue(sourceModifiers)),
                sourceKey: CGKeyCode(sourceKey),
                targetModifiers: CGEventFlags(rawValue: CGEventFlags.RawValue(targetModifiers)),
                targetKey: CGKeyCode(targetKey),
                id: id,
                enabled: enabled
            )
        }
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
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        case 65535: return "None"
        default: return "キーコード \(keyCode)"
        }
    }
    
    static func modifierIndex(_ modifiers: CGEventFlags) -> Int {
        if modifiers.contains(.maskShift) { return 0 }
        if modifiers.contains(.maskControl) { return 1 }
        if modifiers.contains(.maskCommand) { return 2 }
        if modifiers.contains(.maskAlternate) { return 3 }
        return 4  // None
    }
    
    // 複数の修飾キーを配列に分解（最大3つ）
    static func splitModifiers(_ modifiers: CGEventFlags) -> [CGEventFlags] {
        var result: [CGEventFlags] = []
        
        if modifiers.contains(.maskShift) {
            result.append(.maskShift)
        }
        if modifiers.contains(.maskControl) {
            result.append(.maskControl)
        }
        if modifiers.contains(.maskCommand) {
            result.append(.maskCommand)
        }
        if modifiers.contains(.maskAlternate) {
            result.append(.maskAlternate)
        }
        
        // 3つまでに制限し、足りない分はNone（空）で埋める
        while result.count < 3 {
            result.append([])
        }
        
        return Array(result.prefix(3))
    }
    
    // 修飾キーから選択インデックスを取得
    static func modifierToIndex(_ modifier: CGEventFlags) -> Int {
        if modifier.contains(.maskShift) { return 0 }
        if modifier.contains(.maskControl) { return 1 }
        if modifier.contains(.maskCommand) { return 2 }
        if modifier.contains(.maskAlternate) { return 3 }
        return 4  // None
    }
    
    // 修飾キーまたはキーから選択インデックスを取得（2行目用）
    static func modifierOrKeyToIndex(_ modifier: CGEventFlags, isModifier: Bool) -> Int {
        // まず修飾キーとしてチェック
        if modifier.contains(.maskShift) { return 0 }
        if modifier.contains(.maskControl) { return 1 }
        if modifier.contains(.maskCommand) { return 2 }
        if modifier.contains(.maskAlternate) { return 3 }
        
        // 空の場合はNone
        if modifier.isEmpty {
            return 34  // None at end of list
        }
        
        // 上位ビットにキーコードが格納されている場合
        let keyCode = CGKeyCode((modifier.rawValue >> 32) & 0xFFFF)
        if keyCode > 0 && keyCode != 65535 {
            // キーコードのインデックスを計算（4個の修飾キーの後）
            return 4 + keyIndex(keyCode)
        }
        
        // それ以外は None
        return 34
    }
    
    // 選択ボックスの名前から修飾キーまたはキーコードを取得
    static func modifierOrKeyFlagFromName(_ name: String) -> CGEventFlags {
        // まず修飾キーとしてチェック
        switch name {
        case "Shift": return .maskShift
        case "Control": return .maskControl
        case "Command": return .maskCommand
        case "Option": return .maskAlternate
        case "None": return []
        default:
            // 通常のキーの場合は、キーコードをCGEventFlagsに変換（特殊なエンコード）
            // rawValueの上位ビットを使用してキーコードを格納
            let keyCode = keyCodeFromName(name)
            if keyCode == 65535 { return [] }  // None
            // キーコードをビットシフトして格納（修飾キーと区別するため）
            return CGEventFlags(rawValue: CGEventFlags.RawValue(keyCode) << 32)
        }
    }
    
    static func keyIndex(_ keyCode: CGKeyCode) -> Int {
        switch keyCode {
        case 49: return 0   // Space
        case 36: return 1   // Return
        case 51: return 2   // Delete
        case 53: return 3   // Escape
        case 0: return 4    // A
        case 11: return 5   // B
        case 8: return 6    // C
        case 2: return 7    // D
        case 14: return 8   // E
        case 3: return 9    // F
        case 5: return 10   // G
        case 4: return 11   // H
        case 34: return 12  // I
        case 38: return 13  // J
        case 40: return 14  // K
        case 37: return 15  // L
        case 46: return 16  // M
        case 45: return 17  // N
        case 31: return 18  // O
        case 35: return 19  // P
        case 12: return 20  // Q
        case 15: return 21  // R
        case 1: return 22   // S
        case 17: return 23  // T
        case 32: return 24  // U
        case 9: return 25   // V
        case 13: return 26  // W
        case 7: return 27   // X
        case 16: return 28  // Y
        case 6: return 29   // Z
        case 65535: return 30  // None
        default: return 0
        }
    }
    
    static func modifierFlagFromName(_ name: String) -> CGEventFlags {
        switch name {
        case "Shift": return .maskShift
        case "Control": return .maskControl
        case "Command": return .maskCommand
        case "Option": return .maskAlternate
        case "None": return []
        default: return []
        }
    }
    
    static func keyCodeFromName(_ name: String) -> CGKeyCode {
        switch name {
        case "Space": return 49
        case "Return": return 36
        case "Delete": return 51
        case "Escape": return 53
        case "A": return 0
        case "B": return 11
        case "C": return 8
        case "D": return 2
        case "E": return 14
        case "F": return 3
        case "G": return 5
        case "H": return 4
        case "I": return 34
        case "J": return 38
        case "K": return 40
        case "L": return 37
        case "M": return 46
        case "N": return 45
        case "O": return 31
        case "P": return 35
        case "Q": return 12
        case "R": return 15
        case "S": return 1
        case "T": return 17
        case "U": return 32
        case "V": return 9
        case "W": return 13
        case "X": return 7
        case "Y": return 16
        case "Z": return 6
        case "None": return 65535
        default: return 49
        }
    }
}
