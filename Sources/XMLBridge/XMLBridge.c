#include "XMLBridge.h"
#include <string.h>
#include <stdlib.h>

/// Parse an XML string into a bridge handle with an XPath context.
/// Caller MUST free with `workdock_xml_free`. Returns NULL on parse error.
workdock_xml_t *workdock_xml_parse(const char *xml, size_t len) {
    workdock_xml_t *h = (workdock_xml_t *)calloc(1, sizeof(workdock_xml_t));
    if (!h) return NULL;
    h->doc = xmlReadMemory(xml, (int)len, NULL, NULL, XML_PARSE_NOENT | XML_PARSE_RECOVER);
    if (!h->doc) { free(h); return NULL; }
    h->ctx = xmlXPathNewContext(h->doc);
    if (!h->ctx) { xmlFreeDoc(h->doc); free(h); return NULL; }
    return h;
}

/// Parse an HTML string into a bridge handle with an XPath context.
/// (Lombok's `etree.HTML` equivalent — recovers from broken markup.)
workdock_xml_t *workdock_html_parse(const char *html, size_t len, const char *encoding) {
    workdock_xml_t *h = (workdock_xml_t *)calloc(1, sizeof(workdock_xml_t));
    if (!h) return NULL;
    const char *enc = (encoding && strlen(encoding) > 0) ? encoding : "utf-8";
    h->doc = htmlReadMemory(html, (int)len, NULL, enc,
                            HTML_PARSE_RECOVER | HTML_PARSE_NODEFDTD | HTML_PARSE_NOWARNING | HTML_PARSE_NOERROR);
    if (!h->doc) { free(h); return NULL; }
    h->ctx = xmlXPathNewContext(h->doc);
    if (!h->ctx) { xmlFreeDoc(h->doc); free(h); return NULL; }
    return h;
}

/// Evaluate an XPath expression. Returns a `;`-joined string of all
/// matching text values. Empty result returns NULL (caller checks).
/// Callers should prefer `workdock_xpath_eval_first` for single-value lookups.
char *workdock_xpath_eval(workdock_xml_t *h, const char *expr) {
    if (!h || !h->ctx) return NULL;
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(BAD_CAST expr, h->ctx);
    if (!obj) return NULL;
    char *result = NULL;
    if (obj->type == XPATH_NODESET && obj->nodesetval) {
        xmlNodeSetPtr set = obj->nodesetval;
        size_t total = 0;
        for (int i = 0; i < set->nodeNr; i++) {
            xmlChar *s = xmlNodeGetContent(set->nodeTab[i]);
            if (s) { total += strlen((char*)s) + 1; xmlFree(s); }
        }
        if (total == 0) { xmlXPathFreeObject(obj); return NULL; }
        result = (char *)calloc(total, 1);
        for (int i = 0; i < set->nodeNr; i++) {
            xmlChar *s = xmlNodeGetContent(set->nodeTab[i]);
            if (s) {
                if (i > 0) strcat(result, ";");
                strcat(result, (char*)s);
                xmlFree(s);
            }
        }
    }
    xmlXPathFreeObject(obj);
    return result;
}

/// First match's text content only. Returns NULL if no match.
char *workdock_xpath_eval_first(workdock_xml_t *h, const char *expr) {
    if (!h || !h->ctx) return NULL;
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(BAD_CAST expr, h->ctx);
    if (!obj) return NULL;
    char *result = NULL;
    if (obj->type == XPATH_NODESET && obj->nodesetval && obj->nodesetval->nodeNr > 0) {
        xmlChar *s = xmlNodeGetContent(obj->nodesetval->nodeTab[0]);
        if (s) {
            result = strdup((char*)s);
            xmlFree(s);
        }
    }
    xmlXPathFreeObject(obj);
    return result;
}

/// Count of nodes matched by `expr`. 0 on error or empty.
int workdock_xpath_count(workdock_xml_t *h, const char *expr) {
    if (!h || !h->ctx) return 0;
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(BAD_CAST expr, h->ctx);
    if (!obj) return 0;
    int n = 0;
    if (obj->type == XPATH_NODESET && obj->nodesetval) n = obj->nodesetval->nodeNr;
    xmlXPathFreeObject(obj);
    return n;
}

/// Get the attribute value (as string) of the first node matching `expr`.
/// `attr` is the attribute name without `@`. NULL if missing.
char *workdock_xpath_attr_first(workdock_xml_t *h, const char *expr, const char *attr) {
    if (!h || !h->ctx) return NULL;
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(BAD_CAST expr, h->ctx);
    if (!obj) return NULL;
    char *result = NULL;
    if (obj->type == XPATH_NODESET && obj->nodesetval && obj->nodesetval->nodeNr > 0) {
        xmlChar *s = xmlGetProp(obj->nodesetval->nodeTab[0], BAD_CAST attr);
        if (s) { result = strdup((char*)s); xmlFree(s); }
    }
    xmlXPathFreeObject(obj);
    return result;
}

void workdock_xml_free(workdock_xml_t *h) {
    if (!h) return;
    if (h->ctx) xmlXPathFreeContext(h->ctx);
    if (h->doc) xmlFreeDoc(h->doc);
    free(h);
}

void workdock_free_string(char *s) {
    if (s) free(s);
}
