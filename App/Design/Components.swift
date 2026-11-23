import SwiftUI

/// Gemeinsame Bausteine. Farben nie als einziges Statussignal (SPEC 1.4): Status steht immer als Text daneben.
struct SymbolBadge: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: 40, height: 40)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

extension View {
    /// „Fertig“ über der Tastatur, damit Zahlenfelder ohne Eingabetaste schließbar sind.
    func keyboardDoneButton(_ focus: FocusState<Bool>.Binding) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { focus.wrappedValue = false }.accessibilityIdentifier("keyboardDone")
            }
        }
    }
}
