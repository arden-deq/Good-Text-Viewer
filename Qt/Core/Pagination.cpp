#include "Pagination.h"

#include <QFontDatabase>
#include <QFontMetricsF>
#include <QPainter>
#include <QTextLayout>
#include <QVarLengthArray>

#include <algorithm>
#include <cmath>
#include <utility>

namespace reader {
namespace {

bool paragraphBreak(QChar ch) { return ch == u'\r' || ch == u'\n' || ch == u'\u2028' || ch == u'\u2029'; }
bool hangul(QChar ch)
{
    const auto u = ch.unicode();
    return (u >= 0x1100 && u <= 0x11ff) || (u >= 0x3130 && u <= 0x318f) || (u >= 0xac00 && u <= 0xd7a3);
}
QTextOption textOption(const QFontMetricsF &metrics)
{
    QTextOption option;
    option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);
    option.setTabStopDistance(metrics.horizontalAdvance(u' ') * 4);
    return option;
}

struct Padding { int first = 0, closer = 0; qreal closerX = 0; };
Padding closingPadding(QStringView s, qreal width, const QFontMetricsF &metrics)
{
    if (s.empty()) return {};
    int last = int(s.size()) - 1;
    while (last >= 0 && s[last].isSpace()) --last;
    if (last < 0 || !QStringView(u"』」】》〉〕）)]}").contains(s[last])) return {};
    int start = last;
    while (start > 0 && (s[start - 1] == u' ' || s[start - 1] == u'\u3000')) --start;
    if (last - start < 8 || s.first(start).contains(u'\t') || s.first(start).isRightToLeft()) return {};
    const auto closerX = width - metrics.horizontalAdvance(s[last]) - 1.0;
    const auto prefix = metrics.horizontalAdvance(s.first(start).toString());
    const auto natural = metrics.horizontalAdvance(s.sliced(start, last - start).toString());
    if (prefix >= closerX || prefix + natural <= closerX) return {};
    // Treat the padding as visual whitespace; keep every source character
    // addressable without relying on a font engine to shape negative spacing.
    return {start, last, closerX};
}

} // namespace

QFont readingFont(int size, int spacingTenths)
{
    QFont font;
#if defined(Q_OS_MACOS) || defined(Q_OS_WIN)
    static const auto bundledFamilies = [] {
        const auto id = QFontDatabase::addApplicationFont(QStringLiteral(":/Assets/Fonts/NotoSerifKR-Medium.otf"));
        return QFontDatabase::applicationFontFamilies(id);
    }();
    font.setWeight(QFont::Medium);
#endif
#ifdef Q_OS_MACOS
    font.setFamilies(bundledFamilies + QStringList{QStringLiteral("AppleMyungjo"), QStringLiteral("Times New Roman")});
#elif defined(Q_OS_WIN)
    font.setFamilies(bundledFamilies + QStringList{QStringLiteral("Batang"), QStringLiteral("Malgun Gothic"), QStringLiteral("Times New Roman")});
#else
    font.setFamilies({QStringLiteral("Noto Serif CJK KR"), QStringLiteral("serif")});
#endif
    font.setStyleHint(QFont::Serif);
    font.setPixelSize(size);
    font.setLetterSpacing(QFont::AbsoluteSpacing, spacingTenths / 10.0);
    return font;
}

void paginate(const QString &text, const Layout &layout, const Cancel &cancel, const PageSink &sink)
{
    const QFontMetricsF metrics(layout.font);
    const auto lineStep = std::ceil(std::max(metrics.height(), layout.font.pixelSize() * 1.72));
    const auto paragraphGap = layout.font.pixelSize() * .72;
    const auto width = std::max(1, layout.page.width());
    const auto height = std::max(1, layout.page.height());
    const auto option = textOption(metrics);
    const QStringView source(text);
    Pages batch;
    Page page;
    qreal y = 0;
    qsizetype count = 0;
    const auto addPage = [&](qsizetype end) {
        page.end = end;
        batch.push_back(std::move(page));
        page = Page{end, end, {}};
        y = 0;
        ++count;
        if (count == 2 || batch.size() == 32) {
            sink(std::exchange(batch, {}), false);
        }
    };
    const auto ensureRoom = [&](qsizetype pos) {
        if (y && y + lineStep > height) addPage(pos);
    };

    for (qsizetype pos = 0; pos < source.size();) {
        if (cancelled(cancel)) return;
        const auto paragraph = pos;
        auto end = pos;
        while (end < source.size() && !paragraphBreak(source[end])) {
            if ((end & 0xffff) == 0 && cancelled(cancel)) return;
            ++end;
        }
        const auto after = end < source.size() ? end + (source[end] == u'\r' && end + 1 < source.size() && source[end + 1] == u'\n' ? 2 : 1) : end;
        if (pos == end) {
            ensureRoom(pos);
            y += lineStep + paragraphGap;
        }
        auto lead = pos;
        while (lead < end && source[lead].isSpace()) ++lead;
        qreal indent = 0;
        const auto maxIndent = width * .35;
        for (auto i = pos; i < lead && indent < maxIndent; ++i)
            indent += source[i] == u'\t' ? option.tabStopDistance() : metrics.horizontalAdvance(source[i]);
        indent = std::min(indent, maxIndent);

        // Normal paragraphs are shaped once. A pathological single-line file is
        // shaped in bounded windows and its last (unstable) line is rolled back.
        while (pos < end) {
            if (cancelled(cancel)) return;
            auto limit = std::min(end, pos + 16384);
            if (limit < end && source[limit].isLowSurrogate()) --limit;
            const auto chunk = source.sliced(pos, limit - pos);
            const auto padding = pos == paragraph && limit == end ? closingPadding(chunk, width, metrics) : Padding{};
            if (padding.closer) {
                ensureRoom(pos);
                page.lines.push_back({pos, int(chunk.size()), 0.0f, float(y), float(metrics.ascent()),
                    padding.first, padding.closer, float(padding.closerX)});
                y += lineStep;
                break;
            }
            QTextLayout shape(chunk.toString(), layout.font);
            shape.setTextOption(option);
            shape.beginLayout();
            auto consumed = pos;
            for (auto line = shape.createLine(); line.isValid(); line = shape.createLine()) {
                if (cancelled(cancel)) return;
                const int start = line.textStart();
                const auto location = pos + start;
                const auto x = location == paragraph ? 0 : indent;
                line.setLineWidth(std::max<qreal>(1, width - x));
                auto stop = start + line.textLength();
                if (stop < chunk.size() && stop > start && hangul(chunk[stop - 1]) && hangul(chunk[stop])) {
                    auto wordStart = stop;
                    while (wordStart > start && !chunk[wordStart - 1].isSpace()) --wordStart;
                    if (wordStart > start && pos + wordStart > lead) {
                        line.setNumColumns(wordStart - start, width - x);
                        stop = start + line.textLength();
                    }
                }
                if (limit < end && stop == chunk.size() && consumed > pos) break;
                if (stop <= start) break;
                ensureRoom(location);
                page.lines.push_back({location, stop - start, float(x), float(y), float(line.ascent())});
                y += lineStep;
                consumed = pos + stop;
            }
            shape.endLayout();
            if (consumed <= pos) break;
            pos = consumed;
        }
        if (end > paragraph) y += paragraphGap;
        pos = after;
    }
    if (cancelled(cancel)) return;
    page.end = text.size();
    batch.push_back(std::move(page));
    sink(std::move(batch), true);
}

size_t pageAt(const Pages &pages, qsizetype anchor)
{
    const auto it = std::upper_bound(pages.begin(), pages.end(), anchor,
        [](qsizetype pos, const Page &p) { return pos < p.start; });
    return it == pages.begin() ? 0 : size_t(it - pages.begin() - 1);
}

void drawPage(QPainter &painter, const QPointF &origin, const QString &text, const QFont &font, const Page &page)
{
    painter.setFont(font);
    const QStringView source(text);
    for (const auto &line : page.lines) {
        const auto row = source.sliced(line.start, line.length);
        auto at = origin + QPointF(line.x, line.y);
        if (line.paddedCloser) {
            at.ry() += line.ascent;
            painter.drawText(at, row.first(line.prefixLength).toString());
            painter.drawText(at + QPointF(line.closerX, 0), row.sliced(line.paddedCloser, 1).toString());
        } else if (!row.contains(u'\t')) {
            at.ry() += line.ascent;
            painter.drawText(at, row.toString());
        } else {
            QTextLayout laidOut(row.toString(), font);
            auto option = textOption(QFontMetricsF(font));
            option.setWrapMode(QTextOption::NoWrap);
            laidOut.setTextOption(option);
            laidOut.beginLayout();
            auto shaped = laidOut.createLine();
            if (shaped.isValid()) { shaped.setPosition({0, 0}); shaped.setLineWidth(1e9); }
            laidOut.endLayout();
            laidOut.draw(&painter, at);
        }
    }
}

} // namespace reader
