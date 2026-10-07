import Foundation

extension UserDefaults {
    var floatingTabOrigin: NSPoint? {
        get {
            guard let values = array(forKey: "floatingTabOrigin") as? [Double],
                  values.count == 2,
                  values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
            return NSPoint(x: values[0], y: values[1])
        }
        set {
            guard let newValue else {
                removeObject(forKey: "floatingTabOrigin")
                return
            }
            guard newValue.x.isFinite, newValue.y.isFinite,
                  newValue.x >= 0, newValue.y >= 0 else { return }
            set([Double(newValue.x), Double(newValue.y)], forKey: "floatingTabOrigin")
        }
    }
}
