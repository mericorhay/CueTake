import Foundation

extension Array {
    /// The element at `index`, or nil when an edit has since removed it.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
