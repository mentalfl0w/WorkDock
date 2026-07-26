import Foundation

/// Standalone test for FujianEducationSpider — run from terminal.
///
/// Usage: swift run spider-test
///
/// Verifies login + unread count + unread documents list, with delays to
/// avoid being flagged as a crawler.
@main
struct SpiderTest {
    static func main() async {
        let username = "4135010385002"
        let password = "abcd,1234"

        print("=== Spider Test ===")
        print("[1/4] Logging in as \(username)...")
        let spider: FujianEducationSpider
        do {
            spider = try await FujianEducationSpider(username: username, password: password)
        } catch {
            print("❌ Login failed: \(error)")
            return
        }
        print("✅ Login succeeded, isLoggedIn=\(await spider.isLoggedIn)")

        // Delay to avoid crawler detection.
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        print("\n[2/4] Fetching unread count...")
        do {
            let count = try await spider.unreadCount()
            print("✅ Unread count: \(count)")
        } catch {
            print("❌ Unread count failed: \(error)")
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        print("\n[3/4] Fetching unread documents (page 1, size 10)...")
        do {
            let docs = try await spider.unreadDocuments(pageSize: 10, start: 1)
            print("✅ Unread documents: \(docs.count)")
            for doc in docs.prefix(5) {
                print("  - [\(doc.urgency)] \(doc.title)")
                print("    来自: \(doc.publisher)  时间: \(doc.publishedAt)")
                print("    文号: \(doc.docMark)  UNID: \(doc.id)")
            }
        } catch {
            print("❌ Unread documents failed: \(error)")
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        print("\n[4/4] Fetching read documents count...")
        do {
            let count = try await spider.readCount()
            print("✅ Read count: \(count)")
        } catch {
            print("❌ Read count failed: \(error)")
        }

        print("\n=== Test complete ===")
        print("Cookies: \(await spider.cookies().map { "\($0.name)=\($0.value.prefix(15))" })")
    }
}
