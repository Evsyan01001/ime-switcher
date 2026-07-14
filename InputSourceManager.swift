import Carbon

// MARK: - 输入法查询与切换 (Carbon TIS API)

/// 根据输入法 ID 查找 TISInputSource
func findInputSource(withID id: String) -> TISInputSource? {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
        return nil
    }
    for source in list {
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if sourceID == id {
                return source
            }
        }
    }
    return nil
}

/// 切换到指定输入法
func selectInputSource(id: String) {
    guard let source = findInputSource(withID: id) else {
        print("⚠️ 找不到输入法: \(id)")
        return
    }
    let result = TISSelectInputSource(source)
    if result == noErr {
        print("✅ 已切换到: \(id)")
    } else {
        print("⚠️ 切换失败,错误码 \(result)")
    }
}

/// 获取当前实际选中的输入法 ID
func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

/// 获取所有可选的键盘输入法列表 (ID, 名称)
func selectableInputSources() -> [(id: String, name: String)] {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    var results: [(String, String)] = []
    for source in list {
        guard let catPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else { continue }
        let category = Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
        guard category == kTISCategoryKeyboardInputSource as String else { continue }

        var selectable = false
        if let selPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
            selectable = Unmanaged<CFBoolean>.fromOpaque(selPtr).takeUnretainedValue() == kCFBooleanTrue
        }
        guard selectable else { continue }

        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        var name = id
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
        results.append((id, name))
    }
    return results
}

/// 根据输入法 ID 获取本地化名称
func inputSourceName(forID id: String) -> String? {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
        return nil
    }
    for source in list {
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if sourceID == id {
                if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                    return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                }
            }
        }
    }
    return nil
}
