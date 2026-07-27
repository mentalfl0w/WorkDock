import Foundation
import XMLBridge
import os

/// Swift facade over the libxml2 C bridge.
///
/// Mirrors the `lxml.etree` usage pattern from the original Python spider:
/// parse once, then issue XPath queries that return strings or counts.
/// All C memory is owned by this type and freed on deinit.
public final class XMLDocument {
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "XML")
    private var handle: UnsafeMutablePointer<workdock_xml_t>?

    /// Parse an XML string (lxml's `etree.XML`).
    public init(xml: String) throws {
        let bytes = Array(xml.utf8)
        let count = bytes.count
        let result: UnsafeMutablePointer<workdock_xml_t>? = bytes.withUnsafeBufferPointer { buf in
            workdock_xml_parse(buf.baseAddress, count)
        }
        guard let h = result else { throw XMLError.parseFailed }
        handle = h
    }

    /// Parse raw XML bytes — libxml2 auto-detects encoding from the XML
    /// declaration (`<?xml encoding="gb2312"?>`). Prefer this for HTTP
    /// responses where charset may differ from UTF-8.
    public init(xmlData: Data) throws {
        let count = xmlData.count
        let result: UnsafeMutablePointer<workdock_xml_t>? = xmlData.withUnsafeBytes { raw in
            workdock_xml_parse(raw.baseAddress, count)
        }
        guard let h = result else { throw XMLError.parseFailed }
        handle = h
    }

    /// Parse an HTML string (lxml's `etree.HTML`), recovering from broken markup.
    public init(html: String, encoding: String = "utf-8") throws {
        let bytes = Array(html.utf8)
        let count = bytes.count
        let result: UnsafeMutablePointer<workdock_xml_t>? = bytes.withUnsafeBufferPointer { buf in
            workdock_html_parse(buf.baseAddress, count, encoding)
        }
        guard let h = result else { throw XMLError.parseFailed }
        handle = h
    }

    /// Parse raw HTML bytes — libxml2 auto-detects encoding from meta tags.
    public init(htmlData: Data, encoding: String? = nil) throws {
        let count = htmlData.count
        let enc = encoding ?? ""
        let result: UnsafeMutablePointer<workdock_xml_t>? = htmlData.withUnsafeBytes { raw in
            workdock_html_parse(raw.baseAddress, count, enc)
        }
        guard let h = result else { throw XMLError.parseFailed }
        handle = h
    }

    deinit {
        if let h = handle { workdock_xml_free(h) }
    }

    /// First match's text content, or nil if no match (lxml `.xpath(...)[0]` with try/catch).
    public func first(_ expr: String) -> String? {
        guard let h = handle,
              let raw = workdock_xpath_eval_first(h, expr) else { return nil }
        let s = String(cString: raw)
        workdock_free_string(raw)
        return s
    }

    /// All matches' text, `;`-joined (lxml `.xpath(...)` returning a list).
    public func all(_ expr: String) -> [String] {
        guard let h = handle,
              let raw = workdock_xpath_eval(h, expr) else { return [] }
        let s = String(cString: raw)
        workdock_free_string(raw)
        return s.isEmpty ? [] : s.components(separatedBy: ";")
    }

    /// Count of nodes matching `expr` (lxml `len(.xpath(...))`).
    public func count(_ expr: String) -> Int {
        guard let h = handle else { return 0 }
        return Int(workdock_xpath_count(h, expr))
    }

    /// Attribute value of the first node matching `expr`.
    public func attr(_ expr: String, _ name: String) -> String? {
        guard let h = handle,
              let raw = workdock_xpath_attr_first(h, expr, name) else { return nil }
        let s = String(cString: raw)
        workdock_free_string(raw)
        return s
    }
}

public enum XMLError: Error {
    case parseFailed
}
