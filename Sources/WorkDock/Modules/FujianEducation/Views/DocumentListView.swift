import SwiftUI

struct DocumentListView: View {
    let documents: [DocumentSummary]
    let isLoading: Bool
    let onRefresh: () -> Void
    let onSelect: (DocumentSummary) -> Void
    var currentPage: Int = 1
    var totalPages: Int = 1
    var onPageChange: (Int) -> Void = { _ in }
    var pageSize: Int = 20
    var onPageSizeChange: (Int) -> Void = { _ in }
    var body: some View {
        VStack(spacing: 8) {
            // Header: count + page size + refresh
            HStack {
                Text(L.totalCount(totalCountDisplay, page: currentPage, total: totalPages))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(L.pageSize, selection: Binding(
                    get: { pageSize },
                    set: { onPageSizeChange($0) }
                )) {
                    Text(L.pageSizeLabel(10)).tag(10)
                    Text(L.pageSizeLabel(20)).tag(20)
                    Text(L.pageSizeLabel(40)).tag(40)
                }
                .pickerStyle(.menu)
                Button(action: onRefresh) {
                    Label(L.refresh, systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 10))

            if isLoading && documents.isEmpty {
                Spacer()
                ProgressView().scaleEffect(0.8)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(documents, id: \.id) { doc in
                            Button(action: { onSelect(doc) }) {
                                DocumentRow(doc: doc)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                }
            }

            // Page navigation
            if totalPages > 1 {
                HStack(spacing: 12) {
                    Button {
                        onPageChange(currentPage - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentPage <= 1)
                    .buttonStyle(.bordered)

                    Spacer()
                    Text("\(currentPage) / \(totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button {
                        onPageChange(currentPage + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentPage >= totalPages)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(in: .rect(cornerRadius: 10))
            }
        }
    }

    private var totalCountDisplay: Int {
        max(documents.count, 0)
    }
}

struct DocumentRow: View {
    let doc: DocumentSummary


    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let label = urgencyLabel(doc.urgency) {
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(urgencyColor(for: label).opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(urgencyColor(for: label))
                }
                Text(doc.title)
                    .font(.body)
                    .lineLimit(2)
                Spacer()
            }
            HStack {
                Text(doc.publisher).font(.caption)
                Spacer()
                Text(doc.publishedAt).font(.caption2).foregroundStyle(.secondary)
            }
            if !doc.docMark.isEmpty {
                Text(doc.docMark).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 12))
    }
    private func urgencyLabel(_ u: String) -> String? {
        let v = u.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return nil }
        if v.contains("特急") || v == "3" { return L.urgent }
        if v.contains("加急") || v == "2" { return L.rush }
        return L.normal
    }
    private func urgencyColor(for label: String) -> Color {
        if label == L.urgent { return .red }
        if label == L.rush { return .orange }
        return .secondary
    }
}
