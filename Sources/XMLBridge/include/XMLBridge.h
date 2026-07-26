#ifndef WORKDOCK_XML_BRIDGE_H
#define WORKDOCK_XML_BRIDGE_H
#include <libxml/parser.h>
#include <libxml/xpath.h>
#include <libxml/HTMLparser.h>

/// Opaque bridge handle wrapping a parsed document + its root node.
typedef struct {
    xmlDocPtr doc;
    xmlXPathContextPtr ctx;
} workdock_xml_t;

/// Parse an XML string into a bridge handle with an XPath context.
/// Caller MUST free with `workdock_xml_free`. Returns NULL on parse error.
workdock_xml_t *workdock_xml_parse(const char *xml, size_t len);

/// Parse an HTML string into a bridge handle with an XPath context.
workdock_xml_t *workdock_html_parse(const char *html, size_t len, const char *encoding);

/// Evaluate an XPath expression. Returns a `;`-joined string of all
/// matching text values. Empty result returns NULL.
char *workdock_xpath_eval(workdock_xml_t *h, const char *expr);

/// First match's text content only. Returns NULL if no match.
char *workdock_xpath_eval_first(workdock_xml_t *h, const char *expr);

/// Count of nodes matched by `expr`. 0 on error or empty.
int workdock_xpath_count(workdock_xml_t *h, const char *expr);

/// Attribute value (as string) of the first node matching `expr`.
/// `attr` is the attribute name without `@`. NULL if missing.
char *workdock_xpath_attr_first(workdock_xml_t *h, const char *expr, const char *attr);

void workdock_xml_free(workdock_xml_t *h);
void workdock_free_string(char *s);

#endif
