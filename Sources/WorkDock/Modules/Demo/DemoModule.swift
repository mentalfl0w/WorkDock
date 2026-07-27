import SwiftUI

/// Demo module — previews real UI components with mock data.
/// Appears in the gallery below Settings.
public final class DemoModule: Module {
    public let id = "demo"
    public let displayName = L.demoName
    public let icon = "square.grid.2x2"
    public let summary = L.demoSummary
    public let router: NavigationRouter
    public let showsInMenuBar = false
    public let isAuxiliary = true

    public init(router: NavigationRouter) {
        self.router = router
    }

    public var isSignedIn: Bool {
        get async { true }
    }

    public func menuItems() async -> [ModuleMenuItem] {
        []
    }

    @MainActor
    public func mainView() -> AnyView {
        AnyView(DemoModuleView())
    }

    public func start() async {}
    public func stop() async {}
}

// MARK: - View

struct DemoModuleView: View {
    @State private var showDetail = false
    @State private var currentPage = 1
    @State private var pageSize = 10

    var body: some View {
        ModuleContainerView(title: L.demoName) {
            VStack(spacing: 0) {
                // Document list with real DocumentListView
                DocumentListView(
                    documents: mockDocuments,
                    isLoading: false,
                    onRefresh: {},
                    onSelect: { _ in showDetail = true },
                    currentPage: currentPage,
                    totalPages: 3,
                    onPageChange: { currentPage = $0 },
                    pageSize: pageSize,
                    onPageSizeChange: { pageSize = $0 })


            }
        }
        .sheet(isPresented: $showDetail) {
            ZStack {
                GlassBackgroundView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                DocumentDetailView(
                    detail: mockDetail,
                    attachments: mockAttachments,
                    canSignin: true,
                    onClose: { showDetail = false },
                    onSignin: {},
                    onDownloadAttachment: { _, _ in
                        try await Task.sleep(for: .seconds(1))
                    })
            }
            .presentationBackground(.clear)
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Mock Data

    private var mockDocuments: [DocumentSummary] {
        [
            DocumentSummary(id: "1", noteID: "1", title: "关于做好2026年度教育系统安全生产工作的通知", publisher: "福建省教育厅", publishedAt: "2026-01-15", docMark: "闽教安〔2026〕1号", urgency: "特急"),
            DocumentSummary(id: "2", noteID: "2", title: "关于开展2026年春季学期开学检查工作的通知", publisher: "福建省教育厅", publishedAt: "2026-02-01", docMark: "闽教督〔2026〕3号", urgency: "加急"),
            DocumentSummary(id: "3", noteID: "3", title: "关于进一步规范中小学办学行为的通知", publisher: "福建省教育厅基础教育处", publishedAt: "2026-02-20", docMark: "闽教基〔2026〕5号", urgency: ""),
            DocumentSummary(id: "4", noteID: "4", title: "关于做好2026年普通高校招生考试报名工作的通知", publisher: "福建省教育考试院", publishedAt: "2026-03-01", docMark: "闽考院〔2026〕2号", urgency: ""),
            DocumentSummary(id: "5", noteID: "5", title: "关于推进职业教育产教融合的实施方案", publisher: "福建省教育厅职业教育与成人教育处", publishedAt: "2026-03-10", docMark: "闽教职成〔2026〕4号", urgency: "加急"),
            DocumentSummary(id: "6", noteID: "6", title: "关于做好2026年度教师职称评审工作的通知", publisher: "福建省教育厅人事处", publishedAt: "2026-03-15", docMark: "闽教人〔2026〕6号", urgency: ""),
            DocumentSummary(id: "7", noteID: "7", title: "关于加强校园食品安全管理的通知", publisher: "福建省教育厅安全处", publishedAt: "2026-04-01", docMark: "闽教安〔2026〕8号", urgency: "特急"),
            DocumentSummary(id: "8", noteID: "8", title: "关于开展义务教育质量监测的通知", publisher: "福建省教育厅督导处", publishedAt: "2026-04-10", docMark: "闽教督〔2026〕10号", urgency: ""),
        ]
    }

    private var mockDetail: DocumentDetail {
        DocumentDetail(
            id: "1",
            title: "关于做好2026年度教育系统安全生产工作的通知",
            docMark: "闽教安〔2026〕1号",
            publisher: "福建省教育厅",
            publishNote: "请各设区市教育局、省属高校于2026年3月1日前将工作落实情况报送我厅安全处。",
            publicAttribute: "公开",
            priority: L.urgent,
            database: "mock",
            key: "mock-key")
    }

    private var mockAttachments: [Attachment] {
        [
            Attachment(name: "关于做好2026年度教育系统安全生产工作", fileName: "关于做好2026年度教育系统安全生产工作.pdf", url: URL(string: "https://example.com/1.pdf")!),
            Attachment(name: "安全生产自查表", fileName: "安全生产自查表.docx", url: URL(string: "https://example.com/2.docx")!),
            Attachment(name: "工作台账模板", fileName: "工作台账模板.xlsx", url: URL(string: "https://example.com/3.xlsx")!),
        ]
    }
}
