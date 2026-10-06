import SwiftUI

/// Ein Knopf für eine `KireiAction`, mit Symbol, Titel und Tastenkürzel.
public struct ActionButton: View {
    private let action: KireiAction
    private let perform: () -> Void

    public init(_ action: KireiAction, perform: @escaping () -> Void) {
        self.action = action
        self.perform = perform
    }

    public var body: some View {
        Button(action: perform) {
            Label {
                Text(action.title)
            } icon: {
                Image(systemName: action.systemImage)
            }
        }
        .kireiShortcut(action.shortcut)
    }
}

extension View {
    /// Hängt ein Tastenkürzel an, falls die Aktion eines hat.
    @ViewBuilder
    public func kireiShortcut(_ shortcut: Shortcut?) -> some View {
        if let shortcut {
            keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else {
            self
        }
    }
}

extension Shortcut {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case .character(let character): KeyEquivalent(character)
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .space: .space
        case .delete: .delete
        case .escape: .escape
        case .`return`: .`return`
        }
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}
