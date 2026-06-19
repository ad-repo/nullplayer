import SwiftUI

/// Shared selected-pane state for the classic and modern Audio Analysis windows.
final class AudioAnalysisModel: ObservableObject {
    @Published var selectedPane: Int

    static let paneTitles = ["Scope", "Levels", "Spectrogram"]
    static let selectedPaneDefaultsKey = "audioAnalysisSelectedPane"

    init(selectedPane: Int) {
        self.selectedPane = min(max(0, selectedPane), Self.paneTitles.count - 1)
    }
}

/// Shared pane host. Window-specific views provide only the consumer update callback.
struct AudioAnalysisContentView: View {
    @ObservedObject var model: AudioAnalysisModel
    let onPaneChange: (Int) -> Void

    var body: some View {
        ZStack {
            switch model.selectedPane {
            case 1: LevelsPaneView()
            case 2: SpectrogramPaneView()
            default: ScopePaneView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.selectedPane) {
            UserDefaults.standard.set(
                model.selectedPane,
                forKey: AudioAnalysisModel.selectedPaneDefaultsKey
            )
            onPaneChange(model.selectedPane)
        }
    }
}
