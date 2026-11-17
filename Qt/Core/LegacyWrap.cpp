#include "TextDocument.h"

#include <QHash>
#include <QSet>

#include <algorithm>
#include <initializer_list>
#include <utility>
#include <vector>

using namespace Qt::StringLiterals;

namespace reader {
namespace {

bool horizontal(QChar ch) { return ch == u' ' || ch == u'\t' || ch == u'\u00a0' || ch == u'\u3000'; }
bool hangul(QChar ch)
{
    const auto u = ch.unicode();
    return (u >= 0x1100 && u <= 0x11ff) || (u >= 0x3130 && u <= 0x318f) || (u >= 0xac00 && u <= 0xd7a3);
}

qsizetype width(QStringView s)
{
    qsizetype result = 0;
    for (auto ch : s) {
        if (!ch.isLowSurrogate() && !ch.isMark())
            result += ch == u'\t' ? 4 : ch.unicode() < 128 ? 1 : 2;
    }
    return result;
}

QStringView leftTrim(QStringView s) { while (!s.empty() && horizontal(s.front())) s.slice(1); return s; }
QStringView rightTrim(QStringView s) { while (!s.empty() && horizontal(s.back())) s.chop(1); return s; }
QStringView firstToken(QStringView s)
{
    qsizetype n = 0;
    while (n < s.size() && s[n].isLetterOrNumber()) ++n;
    return s.first(n);
}
QStringView lastToken(QStringView s)
{
    auto n = s.size();
    while (n && s[n - 1].isLetterOrNumber()) --n;
    return s.sliced(n);
}
bool structured(QStringView s)
{
    if (s.contains(u'\t') || s.endsWith(u"  ")) return true;
    s = s.trimmed();
    if (s.empty() || QStringView(u"|+┌├└").contains(s.front())) return true;
    int runs = 0, run = 0;
    for (auto ch : s) {
        if (ch == u' ' || ch == u'\u3000') ++run;
        else if (std::exchange(run, 0) >= 2 && ++runs == 2) return true;
    }
    return false;
}
bool terminal(QStringView s)
{
    s = s.trimmed();
    while (!s.empty() && QStringView(u"'\"’”)]}』」】》〉").contains(s.back())) s.chop(1);
    return !s.empty() && QStringView(u".!?。！？…").contains(s.back());
}

using Words = std::initializer_list<QStringView>;
const Words particles = {u"가",u"과",u"는",u"도",u"를",u"만",u"에",u"에게",u"와",u"은",u"을",u"의",u"이",u"까지",u"로",u"으로",u"에서",u"에서는",u"에서도",u"에게는",u"에게서",u"로서",u"로써",u"부터",u"보다"};
const Words suffixes = {u"에게서는",u"에게서",u"에게는",u"에서는",u"에서도",u"으로",u"에서",u"로서",u"로써",u"부터",u"까지",u"에게",u"만으로",u"만이",u"점들을",u"들을",u"들이",u"들과",u"보다",u"가",u"과",u"는",u"도",u"를",u"만",u"에",u"와",u"은",u"을",u"의",u"이",u"로"};
const QSet<QStringView> dictionary = {u"갖다",u"경미",u"관도",u"글자",u"기다리다",u"나가떨어지다",u"단축",u"돌파",u"드나들다",u"둔탁하다",u"멍하다",u"모니터",u"머금다",u"반응",u"받아들이다",u"보장하다",u"복원",u"사회문제",u"산짐승",u"상승",u"생산",u"소탕하다",u"어색하다",u"언제든지",u"없어지다",u"연마",u"영광",u"이치다",u"작업",u"정도",u"지휘",u"차갑다",u"착실",u"철두철미",u"클래스",u"꺼내다",u"타격",u"탈탈",u"특권",u"학살",u"형성",u"형태",u"헤매다",u"확신하다",u"둘러보다"};
bool exact(QStringView s, Words words) { return std::find(words.begin(), words.end(), s) != words.end(); }
bool starts(QStringView s, Words words) { return std::any_of(words.begin(), words.end(), [s](auto w) { return s.startsWith(w); }); }
bool ends(QStringView s, Words words, bool longer = false)
{
    return std::any_of(words.begin(), words.end(), [s, longer](auto w) { return (!longer || s.size() > w.size()) && s.endsWith(w); });
}
QString pairKey(QStringView a, QStringView b) { auto key = a.toString(); key += QChar::Null; key += b; return key; }

bool knownJoin(QStringView left, QStringView right)
{
    auto lookup = [left](QStringView head, QStringView tail = {}) {
        auto word = left.toString(); word += head; word += tail;
        return dictionary.contains(QStringView(word));
    };
    if (lookup(right)) return true;
    const Words extras = {u"이었다면",u"이었지만",u"이었다",u"였지만",u"였기",u"였던",u"였다",u"었다",u"았다",u"웠다",u"궜다",u"했겠지만",u"되었다",u"스러운",u"이기에는",u"이기에",u"하는",u"라서",u"한다",u"하게",u"하고",u"하며",u"하면",u"해서",u"했다",u"하지",u"들인",u"들을",u"되어",u"된",u"한",u"할",u"히",u"들",u"계"};
    for (const auto group : {suffixes, extras})
        for (const auto s : group)
            if (right.size() > s.size() && right.endsWith(s) && lookup(right.chopped(s.size()))) return true;
    if ((exact(right, {u"한",u"할",u"하고",u"한다",u"하게",u"했다",u"하며",u"하면",u"해"}) && lookup(u"하다")) ||
        (right.startsWith(u"내지") && lookup(u"내다")) || (right == u"진" && lookup(u"지다")) ||
        (right.size() > 2 && right.endsWith(u"진다") && lookup(right.chopped(2), u"지다"))) return true;
    static constexpr std::pair<QStringView, QStringView> changes[] = {
        {u"나드는",u"나들다"},{u"러보면서",u"러보다"},{u"갑기만",u"갑다"},{u"다리면서",u"다리다"},
        {u"리면서",u"리다"},{u"리며",u"리다"},{u"금고",u"금다"},{u"이기에는",u"이다"}};
    for (const auto &[ending, lemma] : changes)
        if (right.endsWith(ending) && lookup(right.chopped(ending.size()), lemma)) return true;
    if (!ends(left, particles, true)) {
        if (right == u"들인") return true;
        for (const auto p : particles)
            if (right.size() > p.size() && right.endsWith(p) && exact(right.chopped(p.size()), {u"들",u"어"})) return true;
    }
    return false;
}

bool needsSpace(QStringView a, QStringView b, bool hadSpace, const QSet<QStringView> &tokens,
                const QSet<QStringView> &stems, const QSet<QString> &pairs)
{
    if (a.empty() || b.empty()) return false;
    if (hadSpace) return true;
    const auto x = a.back(), y = b.front();
    if (x.isSpace() || y.isSpace() || QStringView(u"([{『「【《〈“‘\"").contains(x) ||
        QStringView(u",.!?:;)]}』」】》〉”’\"").contains(y)) return false;
    const auto l = lastToken(a), r = firstToken(b);
    if ((x.isNumber() || x == u'%') && exact(r, {u"가",u"과",u"는",u"도",u"라",u"라는",u"라고",u"를",u"만",u"씩",u"에",u"와",u"은",u"을",u"의",u"이",u"까지",u"로",u"으로",u"에서",u"부터",u"보다"})) return false;
    if (!hangul(x) || !hangul(y)) return true;
    if (std::any_of(l.begin(), l.end(), [](QChar c) { return c.isDigit(); }))
        for (const auto c : Words{u"개",u"권",u"대",u"마리",u"명",u"번",u"분",u"시",u"원",u"월",u"일",u"장",u"초"})
            if (r.startsWith(c) && (r == c || exact(r.sliced(c.size()), particles))) return true;
    if (pairs.contains(pairKey(l, r))) return true;
    auto combined = l.toString(); combined += r;
    if (tokens.contains(QStringView(combined)) || stems.contains(QStringView(combined))) return false;
    for (const auto s : suffixes)
        if (r.size() > s.size() && r.endsWith(s) && stems.contains(QStringView(combined).chopped(s.size()))) return false;
    if (r.startsWith(u'하') || r.startsWith(u'했'))
        if (ends(l, {u"야",u"아야",u"어야",u"여야",u"고",u"지",u"게",u"며",u"면서",u"도록",u"려고"})) return true;
    const bool modifier = ends(l, {u"같은",u"그런",u"는",u"다른",u"된",u"란",u"로운",u"많은",u"새로운",u"없는",u"은",u"있는",u"적은",u"저런",u"한",u"할",u"이런",u"일"});
    if (starts(r, {u"것",u"건",u"데",u"때문",u"바",u"수"}) && (modifier || exact(l, {u"본",u"온",u"갈",u"난",u"낼",u"될",u"볼",u"쓴",u"올"}))) return true;
    if (r == u"가" && l.endsWith(u"겠는")) return false;
    if (modifier || (starts(r, {u"없",u"있",u"아니",u"되"}) && ends(l, particles, true))) return true;
    if (starts(r, {u"니없",u"면서",u"스럽",u"적으로",u"적인",u"적으",u"려",u"했",u"하겠",u"하는",u"하며",u"하면",u"하지"}) || exact(r, particles) ||
        exact(r, {u"고",u"니",u"서",u"지",u"워",u"아야",u"아서",u"어야",u"았다",u"었다",u"이었다",u"였다",u"였기",u"었던",u"웠다",u"궜다",u"이나",u"인데",u"이니",u"이었지만",u"이었다면",u"라서",u"리째",u"으며",u"니까",u"서는",u"더라도",u"어나면",u"러났다",u"리지",u"리며",u"지라도",u"지고",u"질지",u"지만",u"면",u"게",u"어",u"히",u"밖에는"})) return false;
    if ((r == u"터" && l.endsWith(u'부')) || (r == u"다" && ends(l, {u"였",u"이었",u"했",u"있었",u"없었",u"됐",u"된",u"이"}))) return false;
    return !knownJoin(l, r);
}

struct Line { QStringView text; qsizetype width; bool join = false; };
} // namespace

QString repairLegacyWraps(const QString &source, const Cancel &cancel)
{
    const QStringView view(source);
    const auto header = view.first(std::min<qsizetype>(512, view.size())).trimmed();
    if (header.startsWith(u"<?xml") || header.startsWith(u"<mediawiki")) return source;
    std::vector<Line> lines;
    QHash<qsizetype, qsizetype> histogram;
    qsizetype measured = 0;
    for (qsizetype offset = 0; offset <= view.size();) {
        if (cancelled(cancel)) return source;
        auto end = offset;
        while (end < view.size() && view[end] != u'\n' && view[end] != u'\r') ++end;
        auto line = view.sliced(offset, end - offset);
        const auto w = width(line);
        lines.push_back({line, w});
        if (w >= 40 && !line.trimmed().empty()) { ++histogram[w]; ++measured; }
        offset = end + 1;
        if (offset < view.size() && view[end] == u'\r' && view[offset] == u'\n') ++offset;
    }
    if (measured < 20) return source;
    qsizetype best = 0, upper = 0;
    qsizetype bestCount = 0;
    auto keys = histogram.keys();
    std::sort(keys.begin(), keys.end());
    qsizetype rank = 0;
    for (const auto w : keys) {
        const auto count = histogram.value(w - 2) + histogram.value(w - 1) + histogram.value(w) + histogram.value(w + 1) + histogram.value(w + 2);
        if (count >= bestCount) { best = w; bestCount = count; }
        rank += histogram.value(w);
        if (!upper && rank > measured * 3 / 4) upper = w;
    }
    if (bestCount < std::max<qsizetype>(8, measured / 5) || best < qsizetype(upper * .85)) return source;
    const auto threshold = std::max<qsizetype>(40, best - 3);
    size_t joins = 0, endings = 0, paragraphEnds = 0;
    for (size_t i = 0; i + 1 < lines.size(); ++i) {
        if (cancelled(cancel)) return source;
        auto &a = lines[i];
        const auto &b = lines[i + 1];
        if (a.width < threshold || a.text.empty() || b.text.empty() || horizontal(b.text.front()) ||
            width(a.text.first(a.text.size() - leftTrim(a.text).size())) > 2 || structured(a.text) || structured(b.text)) continue;
        a.join = true;
        ++joins;
        endings += terminal(a.text);
        if (b.width < threshold && terminal(b.text) && (i + 2 == lines.size() ||
            lines[i + 2].text.trimmed().empty() || horizontal(lines[i + 2].text.front()))) ++paragraphEnds;
    }
    if (joins < std::max<size_t>(4, lines.size() / 20) || endings * 5 >= joins ||
        paragraphEnds < std::max<size_t>(4, joins / 10)) return source;

    QSet<QStringView> tokens, stems;
    QSet<QString> wantedPairs, foundPairs;
    for (size_t i = 0; i + 1 < lines.size(); ++i) {
        if (!lines[i].join) continue;
        const auto a = rightTrim(lines[i].text), b = lines[i + 1].text;
        if (!a.empty() && hangul(a.back()) && hangul(b.front())) wantedPairs.insert(pairKey(lastToken(a), firstToken(b)));
    }
    for (const Line &line : lines) {
        if (wantedPairs.isEmpty()) break;
        if (cancelled(cancel)) return source;
        QStringView previous;
        for (qsizetype i = 0; i < line.text.size();) {
            if (line.text[i].isSpace()) { ++i; continue; }
            const auto start = i;
            while (i < line.text.size() && !line.text[i].isSpace()) ++i;
            const auto chunk = line.text.sliced(start, i - start);
            const auto first = firstToken(chunk);
            if (!previous.empty() && !first.empty() && hangul(previous.back()) && hangul(first.front())) {
                const auto key = pairKey(previous, first);
                if (wantedPairs.contains(key)) foundPairs.insert(key);
            }
            previous = lastToken(chunk);
            for (qsizetype j = 0; j < chunk.size();) {
                if (!chunk[j].isLetterOrNumber()) { ++j; continue; }
                const auto tok = firstToken(chunk.sliced(j));
                j += tok.size();
                if (hangul(tok.back())) tokens.insert(tok);
            }
        }
    }
    for (auto t : tokens) {
        if (cancelled(cancel)) return source;
        stems.insert(t);
        for (const auto s : suffixes)
            if (t.size() > s.size() && t.endsWith(s)) stems.insert(t.chopped(s.size()));
    }
    QString result;
    result.reserve(source.size());
    for (size_t i = 0; i < lines.size(); ++i) {
        if (cancelled(cancel)) return source;
        const Line &line = lines[i];
        auto content = i && lines[i - 1].join ? leftTrim(line.text) : line.text;
        if (line.join) content = rightTrim(content);
        result += content;
        if (line.join) {
            if (needsSpace(content, lines[i + 1].text, content.size() < line.text.size() && horizontal(line.text.back()), tokens, stems, foundPairs)) result += u' ';
        } else if (i + 1 < lines.size()) {
            result += u'\n';
        }
    }
    return result;
}

} // namespace reader
