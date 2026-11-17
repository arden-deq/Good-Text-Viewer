#include "Pagination.h"
#include "TextDocument.h"
#include "../App/ReaderWindow.h"

#include <QCryptographicHash>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QFontMetricsF>
#include <QLabel>
#include <QMenu>
#include <QMenuBar>
#include <QPushButton>
#include <QSignalSpy>
#include <QSlider>
#include <QTemporaryDir>
#include <QTest>
#include <QTextBoundaryFinder>
#include <QTranslator>
#include <QtMath>

#include <iterator>

using namespace reader;
using namespace Qt::StringLiterals;

namespace {
Pages collect(const QString &text, QSize size = {360, 160}, int spacing = 0)
{
    Pages result;
    paginate(text, {size, readingFont(18, spacing)}, {}, [&](Pages &&pages, bool) {
        std::move(pages.begin(), pages.end(), std::back_inserter(result));
    });
    return result;
}

const auto sample = u"  옛날 한글과 지금의 유니코드가 한 문서 안에 자연스럽게 나옵니다. 일시적으로 아주 긴 문장도 줄바꿈이 됩니다. 👨‍👩‍👧‍👦\r\n\r\n"_s;
}

class ReaderTests : public QObject {
    Q_OBJECT
private slots:
    void decoding()
    {
        const auto expected = u"옛날 한글 똠힣"_s;
        for (const auto prefix : {QByteArray(), QByteArray::fromHex("efbbbf")}) {
            auto utf8 = decode(prefix + expected.toUtf8());
            QVERIFY(utf8.document);
            QCOMPARE(utf8.document->text, expected);
            QCOMPARE(utf8.document->encoding, Encoding::Utf8);
        }
        auto cp = decode(QByteArray::fromHex("bfbeb3af20c7d1b1db208c63c652"));
        QVERIFY(cp.document);
        QCOMPARE(cp.document->encoding, Encoding::Cp949);
        QCOMPARE(cp.document->text, expected);
        for (const auto hex : {"feffc624b798b41c0020bb38c11c", "c624b798b41c0020bb38c11c000a", "fffe24c698b71cb4200038bb1cc1"}) {
            auto unicode = decode(QByteArray::fromHex(hex));
            QVERIFY(unicode.document);
            QCOMPARE(unicode.document->text.trimmed(), u"오래된 문서"_s);
        }
        QVERIFY(decode({}).document);
        QVERIFY(!decode(QByteArray::fromHex("001020304050ff80ff")).document);
        QVERIFY(!decode(QByteArray::fromHex("efbbbf00ff")).document);
        QVERIFY(!decode(QByteArray::fromHex("fffeff")).document);
        auto stopped = std::make_shared<std::atomic_bool>(true);
        QVERIFY(!decode(expected.toUtf8(), true, stopped).document);
    }

    void oldWrapAndModernBreaks()
    {
        const auto original = u" 지난달부터 오래된 문서를 읽던 사람들은 여전히 많은 자료를 열어 보았는데 터무\r\n니없는 이야기도 있었다.\r\n"_s.repeated(24);
        const auto repaired = repairLegacyWraps(original);
        QVERIFY(repaired.contains(u"터무니없는"));
        QVERIFY(!repaired.contains(u"터무\n니없는"));
        QCOMPARE(decode(original.toUtf8(), false).document->text, original);
        for (const auto &document : {sample,
                u"  제목: 고정된 너비로 매번 저장하는 형식입니다. 다음 줄은 다른 항목입니다.\r\n"_s.repeated(44),
                u"| 목차  이름        설명                         페이지 번호 |\r\n"_s.repeated(100),
                u"끝맺음없는 일정한 폭으로 이어지는 구조를 가진 의도적인 문서의 줄 길이\r\n"_s.repeated(44),
                u"Show, in its unbroken paragraphs, every line of legacy English verse.\r\nShort line.\r\n\r\n"_s.repeated(30)}) {
            QCOMPARE(repairLegacyWraps(document), document);
        }
    }

    void englishLegacySample()
    {
        const QString path = QString::fromUtf8(READER_SAMPLES) + u"/The-Harbor-Lantern.txt"_s;
        const auto raw = load(path, false), repaired = load(path);
        QVERIFY(raw.document && repaired.document);
        auto originalLines = raw.document->text;
        originalLines.replace(u"\r\n"_s, u"\n"_s);
        QVERIFY(originalLines.contains(u"burning when Nora\nreached"));
        QVERIFY(repaired.document->text.contains(u"burning when Nora reached"));
    }

    void pagesAndKoreanWords()
    {
        auto pages = collect(sample.repeated(50), {160, 64});
        QCOMPARE(pages.front().start, 0);
        QCOMPARE(pages.back().end, sample.size() * 50);
        for (size_t i = 1; i < pages.size(); ++i) {
            QCOMPARE(pages[i - 1].end, pages[i].start);
            QCOMPARE(pageAt(pages, pages[i].start), i);
        }
        const auto empty = collect({});
        QCOMPARE(empty.size(), 1u);
        QCOMPARE(empty.front().end, 0);
        const auto plain = u"글자를 읽다. 사자후를 아주 많이 들어 노이로제가 생겼다. 일시적으로 적을 압박한다."_s;
        for (const auto width : {115, 121, 128, 136, 147, 176, 192}) {
            const auto fitted = collect(plain, {width, 35});
            for (const auto &page : fitted) {
                for (const auto &line : page.lines) {
                    const auto stop = line.start + line.length;
                    const auto word = plain.indexOf(u"일시적으로");
                    QVERIFY2(stop <= word || stop >= word + 5, qPrintable(QString::number(width) + u" / "_s + plain.mid(line.start, line.length)));
                }
            }
        }
    }

    void indentationPaddingAndSpacing()
    {
        const auto text = u"　　들여쓴 설명이 다음 줄까지 이어지는 문장입니다. 단어가 깨지지 않습니다."_s;
        const auto pages = collect(text, {150, 350});
        QVERIFY(pages.front().lines.size() > 1);
        QCOMPARE(pages.front().lines.front().x, 0.0);
        QVERIFY(pages.front().lines[1].x > 20);
        const auto prefix = u"옵션 : 여성 NPC에 대한 호감 30 상승."_s;
        const auto padding = QString(50, u' ');
        const auto plain = prefix + padding + u'』';
        const QFontMetricsF metrics(readingFont(18, 0));
        // Give the prefix and closer room, while forcing the spaces to compress
        // regardless of the selected platform's font metrics.
        const auto boxWidth = qCeil(metrics.horizontalAdvance(prefix) +
                                    metrics.horizontalAdvance(u'』') +
                                    metrics.horizontalAdvance(padding) / 2);
        const auto box = collect(plain, {boxWidth, 350});
        QCOMPARE(box.front().lines.size(), 1u);
        QCOMPARE(box.front().lines.front().paddedCloser, plain.size() - 1);
        QCOMPARE(box.front().lines.front().length, plain.size());
        QVERIFY(box.front().lines.front().closerX > metrics.horizontalAdvance(prefix));
        const auto more = collect(text, {145, 350}, 20);
        const auto less = collect(text, {145, 350}, -5);
        QVERIFY(more.front().lines.front().length <= less.front().lines.front().length);
    }

    void longSingleLineAndGraphemes()
    {
        const auto text = u"abcdef 가나다라 👨‍👩‍👧‍👦 "_s.repeated(1600);
        auto pages = collect(text, {153, 68});
        QTextBoundaryFinder boundary(QTextBoundaryFinder::Grapheme, text);
        qsizetype offset = 0;
        for (const auto &page : pages) {
            for (const auto &line : page.lines) {
                QCOMPARE(line.start, offset);
                offset += line.length;
                boundary.setPosition(offset);
                QVERIFY(boundary.isAtBoundary());
            }
        }
        QCOMPARE(offset, text.size());
    }

    void progressiveCancellation()
    {
        auto token = std::make_shared<std::atomic_bool>();
        qsizetype calls = 0;
        paginate(sample.repeated(5000), {{480, 580}, readingFont(18, 0)}, token, [&](Pages &&pages, bool done) {
            ++calls;
            QVERIFY(!done);
            QCOMPARE(pages.size(), 2u);
            token->store(true);
        });
        QCOMPARE(calls, 1);
    }

    void navigationPreferencesAndDrag()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const auto path = dir.filePath(u"한글 대용량.TXT"_s);
        const auto config = dir.filePath(u"settings.ini"_s);
        QFile text(path);
        QVERIFY(text.open(QIODevice::WriteOnly));
        QVERIFY(text.write(sample.repeated(1500).toUtf8()) > 0);
        text.close();
        qsizetype stored = 0;
        {
            ReaderWindow window(config);
            QSignalSpy shown(&window, &ReaderWindow::pageShown), completed(&window, &ReaderWindow::layoutFinished);
            window.show();
            window.open(path);
            QTRY_VERIFY_WITH_TIMEOUT(!completed.isEmpty(), 10000);
            QVERIFY(!shown.isEmpty());
            auto *slider = window.findChild<QSlider *>(u"progress"_s);
            QVERIFY(slider);
            const auto y = slider->height() / 2;
            QTest::mousePress(slider, Qt::LeftButton, {}, QPoint(6, y));
            QTest::mouseMove(slider, QPoint(slider->width() * 3 / 4, y));
            QVERIFY(slider->isSliderDown());
            QVERIFY(slider->value() > 7000);
            QTest::mouseRelease(slider, Qt::LeftButton, {}, QPoint(slider->width() * 3 / 4, y));
            QVERIFY(shown.last().front().toLongLong() > sample.size() * 1000);
            auto byName = [&window](const QString &name) {
                const auto controls = window.findChildren<QPushButton *>();
                const auto button = std::find_if(controls.begin(), controls.end(), [&name](auto *b) { return b->accessibleName() == name; });
                return button == controls.end() ? nullptr : *button;
            };
            for (const auto &name : {u"Two-page view"_s, u"Increase font size"_s, u"Increase letter spacing"_s}) {
                auto *b = byName(name);
                QVERIFY(b);
                b->click();
            }
            QTRY_VERIFY_WITH_TIMEOUT(completed.size() >= 2, 10000);
            QCOMPARE(window.findChild<QLabel *>(u"fontValue"_s)->text(), u"19"_s);
            QCOMPARE(window.findChild<QLabel *>(u"spacingValue"_s)->text(), u"0.1"_s);
            stored = shown.last().front().toLongLong();
            QVERIFY(stored > sample.size() * 990);
            window.close();
        }
        ReaderWindow restored(config);
        QSignalSpy restoredPage(&restored, &ReaderWindow::pageShown), finished(&restored, &ReaderWindow::layoutFinished);
        restored.show();
        restored.restoreLastFile();
        QTRY_VERIFY_WITH_TIMEOUT(!finished.isEmpty(), 10000);
        QVERIFY(!restoredPage.isEmpty());
        // Window managers can restore a different content size. The reopened
        // spread should still contain the saved position after repagination.
        QVERIFY(restoredPage.last().first().toLongLong() <= stored);
        const auto buttons = restored.findChildren<QPushButton *>();
        const auto next = std::find_if(buttons.begin(), buttons.end(), [](auto *button) {
            return button->accessibleName() == u"Next page";
        });
        QVERIFY(next != buttons.end());
        QVERIFY((*next)->isEnabled());
        (*next)->click();
        QVERIFY(restoredPage.last().first().toLongLong() > stored);
    }

    void recentFiles()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const auto config = dir.filePath(u"settings.ini"_s);
        const auto first = dir.filePath(u"A & B.txt"_s);
        const auto latest = dir.filePath(u"Recent.txt"_s);
        for (const auto &path : {first, latest}) {
            QFile file(path);
            QVERIFY(file.open(QIODevice::WriteOnly));
            QVERIFY(file.write("A short story.") > 0);
        }
        ReaderSettings prefs(config);
        for (int index = 0; index < 12; ++index) {
            Document document;
            document.path = dir.filePath(QString::number(index) + u".txt"_s);
            prefs.remember(document, true, 0);
        }
        const auto firstDocument = load(first).document;
        QVERIFY(firstDocument);
        prefs.remember(*firstDocument, true, 3);
        prefs.remember(*firstDocument, false, 0);
        QCOMPARE(prefs.recentFiles().size(), 10);
        QCOMPARE(prefs.recentFiles().count(first), 1);
        QCOMPARE(prefs.anchor(*firstDocument, true), 3);

        ReaderWindow window(config);
        QSignalSpy completed(&window, &ReaderWindow::layoutFinished);
        window.show();
        window.open(latest);
        QTRY_VERIFY(!completed.isEmpty());
        auto *recent = window.findChild<QMenu *>(u"recentFiles"_s);
        QVERIFY(recent);
        auto *fileMenu = qobject_cast<QMenu *>(recent->parentWidget());
        QVERIFY(fileMenu);
        QVERIFY(QMetaObject::invokeMethod(fileMenu, "aboutToShow"));
        QCOMPARE(recent->actions().size(), 10);
        QCOMPARE(recent->actions().at(0)->text(), u"Recent.txt"_s);
        QCOMPARE(recent->actions().at(1)->text(), u"A && B.txt"_s);
        recent->actions().at(1)->trigger();
        QTRY_VERIFY(completed.size() >= 2);
    }

    void koreanInterfaceAndLoadError()
    {
        QTranslator translator;
        QVERIFY(translator.load(u":/i18n/GoodTextViewer_ko.qm"_s));
        QVERIFY(QCoreApplication::installTranslator(&translator));
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        ReaderWindow window(dir.filePath(u"settings.ini"_s));
        const auto menus = window.menuBar()->actions();
        QVERIFY(std::any_of(menus.begin(), menus.end(), [](const auto *action) { return action->text() == u"보기"; }));
        const auto buttons = window.findChildren<QPushButton *>();
        QVERIFY(std::any_of(buttons.begin(), buttons.end(), [](const auto *button) {
            return button->accessibleName() == u"글자 크기 늘리기" && button->property("typeAdjustment").toBool();
        }));
        QSignalSpy failed(&window, &ReaderWindow::loadFailed);
        window.open(dir.filePath(u"example.pdf"_s));
        QTRY_COMPARE(failed.size(), 1);
        QCOMPARE(failed.first().first().toString(), u"TXT 파일만 열 수 있습니다."_s);
    }

    void externalCorpus()
    {
        const auto paths = qEnvironmentVariable("GTV_TEST_CORPUS").split(QDir::listSeparator(), Qt::SkipEmptyParts);
        if (paths.isEmpty()) QSKIP("Set GTV_TEST_CORPUS to run local corpus tests.");
        for (const auto &path : paths) {
            QTemporaryDir dir;
            QVERIFY(dir.isValid());
            ReaderWindow window(dir.filePath(u"bench.ini"_s));
            QSignalSpy complete(&window, &ReaderWindow::layoutFinished), failed(&window, &ReaderWindow::loadFailed);
            QElapsedTimer timer;
            qint64 first = -1, indexed = -1, earlyEnd = -1, requested = -1;
            auto *slider = window.findChild<QSlider *>(u"progress"_s);
            QVERIFY(slider);
            connect(&window, &ReaderWindow::pageShown, &window, [&] {
                if (first < 0) {
                    if (!window.grab().isNull()) first = timer.elapsed();
                    QTimer::singleShot(0, &window, [&] {
                        requested = timer.elapsed();
                        QTest::mouseClick(slider, Qt::LeftButton, {}, QPoint(slider->width() - 2, slider->height() / 2));
                    });
                } else if (requested >= 0 && earlyEnd < 0) {
                    if (!window.grab().isNull()) earlyEnd = timer.elapsed() - requested;
                }
            });
            connect(&window, &ReaderWindow::layoutFinished, &window, [&] { indexed = timer.elapsed(); });
            window.show();
            QCoreApplication::processEvents();
            timer.start();
            window.open(path);
            QTRY_VERIFY_WITH_TIMEOUT(!complete.isEmpty() || !failed.isEmpty(), 120000);
            QVERIFY2(failed.isEmpty(), failed.isEmpty() ? "" : qPrintable(failed.first().first().toString()));
            QVERIFY(first >= 0 && indexed >= first);
            QTRY_VERIFY_WITH_TIMEOUT(earlyEnd >= 0, 4000);
            QVERIFY(slider->isEnabled());
            QTest::mouseClick(slider, Qt::LeftButton, {}, QPoint(2, slider->height() / 2));
            QSignalSpy jumped(&window, &ReaderWindow::pageShown);
            timer.restart();
            QTest::mouseClick(slider, Qt::LeftButton, {}, QPoint(slider->width() - 2, slider->height() / 2));
            QVERIFY(!window.grab().isNull());
            const auto seekEnd = timer.elapsed();
            QVERIFY(!jumped.isEmpty());
            QCOMPARE(window.findChild<QLabel *>(u"percent"_s)->text(), u"100%"_s);
            const auto name = QFileInfo(path).fileName();
            const auto bytes = QFileInfo(path).size();
            qInfo().noquote() << name << bytes << "bytes" << complete.first().first().toLongLong() << "pages:"
                << "first paint" << first << "ms, early end + paint" << earlyEnd << "ms, indexed" << indexed
                << "ms, indexed end + paint" << seekEnd << "ms";
        }
    }
};

QTEST_MAIN(ReaderTests)
#include "ReaderTests.moc"
