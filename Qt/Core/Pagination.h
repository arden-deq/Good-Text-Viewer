#pragma once

#include "TextDocument.h"

#include <QFont>
#include <QPointF>
#include <QSize>

#include <functional>
#include <vector>

class QPainter;

namespace reader {

struct Layout { QSize page; QFont font; bool operator==(const Layout &) const = default; };
struct PrintLine {
    qsizetype start;
    int length;
    float x, y, ascent;
    int prefixLength = 0, paddedCloser = 0;
    float closerX = 0;
};
struct Page { qsizetype start = 0, end = 0; std::vector<PrintLine> lines; };
using Pages = std::vector<Page>;
using PageSink = std::function<void(Pages &&, bool)>;

QFont readingFont(int size, int spacingTenths);
void paginate(const QString &text, const Layout &layout, const Cancel &cancel, const PageSink &sink);
size_t pageAt(const Pages &pages, qsizetype anchor);
void drawPage(QPainter &painter, const QPointF &origin, const QString &text, const QFont &font, const Page &page);

} // namespace reader
