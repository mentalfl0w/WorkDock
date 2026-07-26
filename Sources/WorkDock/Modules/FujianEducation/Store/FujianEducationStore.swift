import SwiftUI
import os

enum FujianEducationTab: Hashable { case unread, read, search }

@MainActor
final class FujianEducationStore: ObservableObject {
    @Published var tab: FujianEducationTab = .unread
    @Published var unread: [DocumentSummary] = []
    @Published var read: [DocumentSummary] = []
    @Published var detail: DocumentDetail?
    @Published var attachments: [Attachment] = []
    @Published var selectedDetailID: String?
    @Published var loadingUnread = false
    @Published var loadingRead = false
    @Published var error: String?
    @Published var unreadPage = 1
    @Published var readPage = 1
    @Published var unreadTotal = 0
    @Published var readTotal = 0
    @Published var pageSize: Int = 20
    var unreadPages: Int { max(1, Int(ceil(Double(unreadTotal) / Double(pageSize)))) }
    var readPages: Int { max(1, Int(ceil(Double(readTotal) / Double(pageSize)))) }

    func refresh(module: FujianEducationModule) async {
        FileLog.shared.log("[FJJYT] refresh starting")
        await loadUnread(module: module)
    }

    func loadUnread(module: FujianEducationModule) async {
        loadingUnread = true
        defer { loadingUnread = false }
        do {
            let (docs, total) = try await module.unreadDocuments(pageSize: pageSize, start: (unreadPage - 1) * pageSize + 1)
            unread = docs
            unreadTotal = total
            FileLog.shared.log("[FJJYT] unread page \(unreadPage)/\(unreadPages): \(docs.count) docs, total \(total)")
        } catch {
            FileLog.shared.error("[FJJYT] unread error: \(error)")
            self.error = String(describing: error)
        }
    }

    func loadRead(module: FujianEducationModule) async {
        loadingRead = true
        defer { loadingRead = false }
        do {
            let (docs, total) = try await module.readDocuments(pageSize: pageSize, start: (readPage - 1) * pageSize + 1)
            read = docs
            readTotal = total
        } catch { self.error = String(describing: error) }
    }

    func gotoUnreadPage(_ page: Int, module: FujianEducationModule) async {
        let p = max(1, min(page, unreadPages))
        guard p != unreadPage else { return }
        unreadPage = p
        await loadUnread(module: module)
    }

    func gotoReadPage(_ page: Int, module: FujianEducationModule) async {
        let p = max(1, min(page, readPages))
        guard p != readPage else { return }
        readPage = p
        await loadRead(module: module)
    }

    func loadDetail(module: FujianEducationModule, unid: String) async {
        do {
            let d = try await module.unreadDetail(unid: unid)
            detail = d
            attachments = try await module.attachments(for: d)
        } catch { self.error = String(describing: error) }
    }

    func signin(module: FujianEducationModule) async {
        guard let unid = detail?.id else { return }
        _ = try? await module.signDocument(unid: unid)
    }
}
