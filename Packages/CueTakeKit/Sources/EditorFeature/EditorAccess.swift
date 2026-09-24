import Domain

extension EditorModel {
    /// True when `point` may run now; counted when it does. The app says why when it may not.
    public func allows(_ point: AccessPoint) -> Bool {
        access?(point) ?? true
    }
}
