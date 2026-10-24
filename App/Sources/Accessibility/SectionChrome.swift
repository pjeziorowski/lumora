// App/Sources/Accessibility/SectionChrome.swift
//
// List and form section headers and footers in the high-contrast secondary colour. The
// system draws them in `.secondary`, which the accessibility audit reports as too faint on
// grouped backgrounds (see Palette.swift).

import SwiftUI

/// Header or footer content of a section, in `Color.subdued`.
struct SectionLabel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content.foregroundStyle(.subdued)
    }
}

/// `Section("Title") { … }` with the title in `Color.subdued`.
struct TitledSection<Content: View>: View {
    let title: Text
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            SectionLabel { title }
        }
    }
}
