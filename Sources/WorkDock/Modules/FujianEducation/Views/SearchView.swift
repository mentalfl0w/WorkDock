import SwiftUI

struct SearchView: View {
    let module: FujianEducationModule
    let onSelect: (DocumentSummary) -> Void
    @StateObject private var store = SearchStore()
    @StateObject private var input = SearchInput()

    var body: some View {
        VStack {
            HStack {
                TextField(L.search, text: $input.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard !input.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task { await store.run(module: module, word: input.query, isRead: input.isRead) }
                    }
                Toggle(L.read, isOn: $input.isRead)
                    .font(.caption)
                Button(L.search) {
                    guard !input.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task { await store.run(module: module, word: input.query, isRead: input.isRead) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 10))


            DocumentListView(documents: store.results,
                             isLoading: store.loading,
                             onRefresh: { Task { await store.run(module: module, word: input.query, isRead: input.isRead) } },
                             onSelect: onSelect)
        }
    }
}

@MainActor
final class SearchStore: ObservableObject {
    @Published var results: [DocumentSummary] = []
    @Published var loading = false
    func run(module: FujianEducationModule, word: String, isRead: Bool) async {
        loading = true
        defer { loading = false }
        do {
            let (_, docs) = try await module.search(word, isRead: isRead)
            results = docs
        } catch { }
    }
}

@MainActor
final class SearchInput: ObservableObject {
    @Published var query = ""
    @Published var isRead = true
}
