import SwiftUI

struct SearchView: View {
    let module: FujianEducationModule
    let onSelect: (DocumentSummary) -> Void
    @StateObject private var store = SearchStore()
    @StateObject private var input = SearchInput()

    var body: some View {
        VStack(spacing: 8) {
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
                             onSelect: onSelect,
                             currentPage: store.page,
                             totalPages: store.totalPages,
                             onPageChange: { p in Task { await store.gotoPage(p, module: module) } },
                             pageSize: store.pageSize,
                             onPageSizeChange: { s in store.pageSize = s; Task { await store.run(module: module, word: input.query, isRead: input.isRead) } })
        }
    }
}

@MainActor
final class SearchStore: ObservableObject {
    @Published var results: [DocumentSummary] = []
    @Published var loading = false
    @Published var total = 0
    @Published var page = 1
    @Published var pageSize = 20
    @Published var lastQuery = ""
    @Published var lastIsRead = true
    private var allNoteIDs: [String] = []

    var totalPages: Int { max(1, Int(ceil(Double(total) / Double(pageSize)))) }

    func run(module: FujianEducationModule, word: String, isRead: Bool) async {
        loading = true
        defer { loading = false }
        lastQuery = word
        lastIsRead = isRead
        page = 1
        do {
            let (docs, noteIDs, t) = try await module.search(word, pageSize: pageSize, isRead: isRead)
            results = docs
            allNoteIDs = noteIDs
            total = t
        } catch {
            results = []
            allNoteIDs = []
            total = 0
        }
    }

    func gotoPage(_ p: Int, module: FujianEducationModule) async {
        guard p >= 1, p <= totalPages else { return }
        loading = true
        defer { loading = false }
        page = p
        let from = (p - 1) * pageSize
        let to = min(from + pageSize, allNoteIDs.count)
        guard from < to else { return }
        let pageNoteIDs = Array(allNoteIDs[from..<to])
        do {
            results = try await module.searchPage(noteIDs: pageNoteIDs, isRead: lastIsRead)
        } catch { }
    }
}

@MainActor
final class SearchInput: ObservableObject {
    @Published var query = ""
    @Published var isRead = true
}
