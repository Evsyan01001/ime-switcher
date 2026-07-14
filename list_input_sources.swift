import Cocoa
import Carbon

// 打印当前系统所有可选的输入法 ID 和名称,方便你填写 config.json

guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
    print("无法获取输入法列表")
    exit(1)
}

print("已安装 / 可选的输入法:\n")

for source in list {
    guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
    let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

    var name = "(未知名称)"
    if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
        name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
    }

    var selectable = false
    if let selPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
        selectable = Unmanaged<CFBoolean>.fromOpaque(selPtr).takeUnretainedValue() == kCFBooleanTrue
    }

    if selectable {
        print("ID: \(sourceID)\n名称: \(name)\n---")
    }
}
