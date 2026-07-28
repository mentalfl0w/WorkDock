import SwiftUI

/// Root view for the Fujian Education module — tab navigation between unread,
/// read, and search. The spider is owned by the module; this view reads
/// through it, so all data calls are `async`.
struct FujianEducationRootView: View {
    let module: FujianEducationModule
    @StateObject private var store = FujianEducationStore()
    @State private var signedIn = false
    @State private var showSettings = false
    @ObservedObject var router: NavigationRouter

    var body: some View {
        Group {
            if signedIn {
                mainContent
            } else {
                ModuleContainerView(title: module.displayName) {
                    LoginView(store: module) { (cred: FJJYTCredential, remember: Bool) in
                        FileLog.shared.log("[FJJYT] login attempt: \(cred.identifier)")
                        do {
                            try await module.signIn(username: cred.identifier, password: cred.secret, remember: remember)
                            FileLog.shared.log("[FJJYT] login success, signedIn=true")
                            signedIn = true
                        } catch {
                            FileLog.shared.error("[FJJYT] login failed: \(error)")
                            throw error
                        }
                    }
                }
            }
        }
        .task {
            signedIn = await module.isSignedIn
            if signedIn { await store.refresh(module: module) }
        }
        .onChange(of: signedIn) { _, loggedIn in
            if loggedIn { Task { await store.refresh(module: module) } }
        }
        .onChange(of: store.tab) { _, tab in
            if tab == .read && store.read.isEmpty { Task { await store.loadRead(module: module) } }
        }
        .onChange(of: router.pendingPayload) { _, payload in
            guard let payload, signedIn else { return }
            if let unid = payload["unid"] {
                Task { await store.loadDetail(module: module, unid: unid) }
            }
            if let tab = payload["tab"] {
                switch tab {
                case "unread": store.tab = .unread
                case "read": store.tab = .read
                case "search": store.tab = .search
                default: break
                }
            }
        }
        .sheet(item: $store.detail) { d in
            ZStack {
                GlassBackgroundView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                DocumentDetailView(detail: d,
                                   attachments: store.attachments,
                                   canSignin: store.tab == .unread,
                                   onClose: { store.detail = nil },
                                   onSignin: { Task { await store.signin(module: module) } },
                                   onDownloadAttachment: { src, dest in
                                       try await module.downloadAttachment(url: src, to: dest)
                                   })
            }
            .presentationBackground(.clear)
            .presentationDragIndicator(.visible)
        }
    }

    private var mainContent: some View {
        ModuleContainerView(title: module.displayName) {
            VStack(spacing: 8) {
                tabBar
                content
            }

        }
    }
    private var tabBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $store.tab) {
                Text(L.unread).tag(FujianEducationTab.unread)
                Text(L.read).tag(FujianEducationTab.read)
                Text(L.search).tag(FujianEducationTab.search)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer(minLength: 8)

            Button {
                showSettings.toggle()
            } label: {
                Label(L.settingsLabel, systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                FJJYTSettingsView()
                    .frame(width: 260)
            }

            Button {
                module.signOut()
                signedIn = false
            } label: {
                Label(L.logout, systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var content: some View {
        switch store.tab {
        case .unread:
            DocumentListView(documents: store.unread,
                             isLoading: store.loadingUnread,
                             onRefresh: { Task { await store.loadUnread(module: module) } },
                             onSelect: { doc in
                                 store.selectedDetailID = doc.id
                                 Task { await store.loadDetail(module: module, unid: doc.id) }
                             },
                             currentPage: store.unreadPage,
                             totalPages: store.unreadPages,
                             onPageChange: { p in Task { await store.gotoUnreadPage(p, module: module) } },
                             pageSize: store.pageSize,
                             onPageSizeChange: { s in store.pageSize = s; Task { await store.loadUnread(module: module) } })
        case .read:
            DocumentListView(documents: store.read,
                             isLoading: store.loadingRead,
                             onRefresh: { Task { await store.loadRead(module: module) } },
                             onSelect: { doc in
                                 store.selectedDetailID = doc.id
                                 Task { await store.loadDetail(module: module, unid: doc.id) }
                             },
                             currentPage: store.readPage,
                             totalPages: store.readPages,
                             onPageChange: { p in Task { await store.gotoReadPage(p, module: module) } },
                             pageSize: store.pageSize,
                             onPageSizeChange: { s in store.pageSize = s; Task { await store.loadRead(module: module) } })
        case .search:
            SearchView(module: module) { doc in
                store.selectedDetailID = doc.id
                Task { await store.loadDetail(module: module, unid: doc.id) }
            }
        }
    }
}
