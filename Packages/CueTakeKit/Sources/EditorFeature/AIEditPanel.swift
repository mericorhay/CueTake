import DesignSystem
import Domain
import SwiftUI

/// Starting points for a request to the AI, offered as chips in the composer.
///
/// There is no plan to approve: the composer folds away as soon as you send, the AI takes the
/// studio and makes its changes in front of you, and every one of them is listed and reversible
/// in AI changes. Watching it happen is the review.
enum AIEditPanel {
    static var suggestions: [String] {
        [
            AppLocalization.string("editor.ai.suggest.tighten", bundle: .module),
            AppLocalization.string("editor.ai.suggest.captions", bundle: .module),
            AppLocalization.string("editor.ai.suggest.hook", bundle: .module),
            AppLocalization.string("editor.ai.suggest.title", bundle: .module),
            AppLocalization.string("editor.ai.suggest.look", bundle: .module),
            AppLocalization.string("editor.ai.suggest.energy", bundle: .module),
            AppLocalization.string("editor.ai.suggest.camera", bundle: .module),
        ]
    }
}
