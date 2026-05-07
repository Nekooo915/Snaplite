import Combine
import Foundation
import SwiftUI

/// Single source of truth for runtime state. Owned by `AppDelegate` and
/// observed by the SwiftUI settings view. Whenever `config` is mutated,
/// we rebroadcast to subscribers (menubar / hotkeys) via the closures
/// below — that way SwiftUI doesn't need to know how the app's
/// non-UI side stays in sync.
final class AppState: ObservableObject {
    @Published var config: Config

    /// Called whenever any field of `config` changes. AppDelegate wires
    /// this up to: re-bind hotkeys, update tray menu labels, switch
    /// language, hide/show the menubar icon, persist to disk.
    var onConfigChange: ((Config) -> Void)?

    private var cancellables: Set<AnyCancellable> = []

    init(initial: Config) {
        self.config = initial
        // Use Combine to dedupe redundant assignments that don't actually
        // change the model: SwiftUI bindings often write the same value
        // on every render.
        $config
            .removeDuplicates()
            .sink { [weak self] new in
                self?.onConfigChange?(new)
            }
            .store(in: &cancellables)
    }
}
