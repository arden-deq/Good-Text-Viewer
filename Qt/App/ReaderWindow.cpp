#include "ReaderWindow.h"

#include <QAction>
#include <QCloseEvent>
#include <QDir>
#include <QDragEnterEvent>
#include <QFileDialog>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLabel>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QMimeData>
#include <QPainter>
#include <QPainterPath>
#include <QPushButton>
#include <QShortcut>
#include <QSignalBlocker>
#include <QSlider>
#include <QVBoxLayout>

#include <algorithm>
#include <cmath>
#include <iterator>

#ifdef Q_OS_MACOS
#include "MacTitleBar.h"
#elif defined(Q_OS_WIN)
#include <QProxyStyle>
#include <QStyleOptionMenuItem>
#endif

using namespace Qt::StringLiterals;

namespace reader {
namespace {

constexpr int seekRange = 10000;
const QColor paper(230, 211, 175), ink(42, 33, 24), accent(167, 117, 71);

#ifdef Q_OS_WIN
class CompactMenuStyle final : public QProxyStyle {
public:
    using QProxyStyle::QProxyStyle;

    QSize sizeFromContents(ContentsType type, const QStyleOption *option, const QSize &contents,
                           const QWidget *widget) const override
    {
        auto size = QProxyStyle::sizeFromContents(type, option, contents, widget);
        if (type == CT_MenuBarItem) {
            size.rwidth() -= std::clamp(size.width() - contents.width() - 8, 0, 6);
        } else if (type == CT_MenuItem) {
            const auto *item = qstyleoption_cast<const QStyleOptionMenuItem *>(option);
            if (item && item->menuItemType != QStyleOptionMenuItem::Separator)
                size.rheight() -= std::clamp(size.height() - item->fontMetrics.height() - 6, 0, 3);
        }
        return size;
    }
};
#endif

QPushButton *button(const QString &text, const QString &name, QWidget *parent)
{
    auto *b = new QPushButton(text, parent);
    b->setAccessibleName(name);
    b->setToolTip(name);
    b->setCursor(Qt::PointingHandCursor);
    return b;
}

QIcon bookIcon(bool spread)
{
    QIcon icon;
    for (const auto mode : {QIcon::Off, QIcon::On}) {
        QPixmap pix(32, 32);
        pix.fill(Qt::transparent);
        pix.setDevicePixelRatio(2);
        QPainter p(&pix);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(QPen(mode == QIcon::On ? paper : ink, 1));
        if (spread) {
            p.drawRoundedRect(QRectF(1, 2, 14, 12), 1, 1);
            p.drawLine(QPointF(8, 2), QPointF(8, 14));
        } else {
            p.drawRoundedRect(QRectF(4, 2, 8, 12), 1, 1);
            p.drawLine(QPointF(6, 6), QPointF(10, 6));
            p.drawLine(QPointF(6, 9), QPointF(9, 9));
        }
        p.end();
        icon.addPixmap(pix, QIcon::Normal, mode);
    }
    return icon;
}

enum class TypeAdjustment { FontSize, LetterSpacing };

QPixmap adjustmentIcon(TypeAdjustment adjustment)
{
    QPixmap icon(36, 36);
    icon.fill(Qt::transparent);
    icon.setDevicePixelRatio(2);
    QPainter p(&icon);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(QPen(ink, 1.25, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    QPainterPath lines;
    if (adjustment == TypeAdjustment::FontSize) {
        lines.moveTo(1.5, 14);
        lines.lineTo(5.5, 4);
        lines.lineTo(9.5, 14);
        lines.moveTo(3, 10.5);
        lines.lineTo(8, 10.5);
        lines.moveTo(13.5, 4);
        lines.lineTo(13.5, 14);
        lines.moveTo(11.5, 6);
        lines.lineTo(13.5, 4);
        lines.lineTo(15.5, 6);
        lines.moveTo(11.5, 12);
        lines.lineTo(13.5, 14);
        lines.lineTo(15.5, 12);
    } else {
        lines.moveTo(1.5, 4);
        lines.lineTo(1.5, 14);
        lines.moveTo(16.5, 4);
        lines.lineTo(16.5, 14);
        lines.moveTo(4.5, 9);
        lines.lineTo(13.5, 9);
        lines.moveTo(6.5, 7);
        lines.lineTo(4.5, 9);
        lines.lineTo(6.5, 11);
        lines.moveTo(11.5, 7);
        lines.lineTo(13.5, 9);
        lines.lineTo(11.5, 11);
    }
    p.drawPath(lines);
    p.end();
    return icon;
}

QString dropPath(const QMimeData *data)
{
    for (const auto &url : data->urls()) {
        const QString path = url.toLocalFile();
        if (QFileInfo(path).suffix().compare(u"txt", Qt::CaseInsensitive) == 0) return path;
    }
    return {};
}

class SeekBar final : public QSlider {
public:
    using QSlider::QSlider;
protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);
        const auto y = height() / 2.0;
        const auto position = 5 + (width() - 10) * value() / qreal(maximum());
        p.setPen(QPen(QColor(201, 180, 146), 2, Qt::SolidLine, Qt::RoundCap));
        p.drawLine(QPointF(5, y), QPointF(width() - 5, y));
        if (isEnabled()) {
            p.setPen(QPen(accent, 2, Qt::SolidLine, Qt::RoundCap));
            p.drawLine(QPointF(5, y), QPointF(position, y));
            if (underMouse() || isSliderDown() || hasFocus()) {
                p.setBrush(accent);
                p.setPen(Qt::NoPen);
                p.drawEllipse(QPointF(position, y), 4, 4);
            }
        }
    }
    void mousePressEvent(QMouseEvent *e) override
    {
        if (e->button() != Qt::LeftButton) { e->ignore(); return; }
        setSliderDown(true);
        locate(e);
    }
    void mouseMoveEvent(QMouseEvent *e) override { if (isSliderDown()) locate(e); }
    void mouseReleaseEvent(QMouseEvent *e) override
    {
        if (e->button() == Qt::LeftButton && isSliderDown()) { locate(e); setSliderDown(false); update(); }
    }
    void enterEvent(QEnterEvent *e) override { QSlider::enterEvent(e); update(); }
    void leaveEvent(QEvent *e) override { QSlider::leaveEvent(e); update(); }
private:
    void locate(QMouseEvent *e)
    {
        setSliderPosition(qRound(maximum() * std::clamp((e->position().x() - 5) / std::max(1, width() - 10), 0.0, 1.0)));
        update();
    }
};

class TitleStrip final : public QWidget {
public:
    using QWidget::QWidget;
protected:
    void mousePressEvent(QMouseEvent *event) override
    {
#ifdef Q_OS_MACOS
        if (event->button() == Qt::LeftButton && dragFromTitleBar(*window())) { event->accept(); return; }
#endif
        QWidget::mousePressEvent(event);
    }
};

} // namespace

class ReaderCanvas final : public QWidget {
public:
    explicit ReaderCanvas(ReaderWindow *window) : QWidget(window), reader(window)
    {
        setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
        setAccessibleName(ReaderWindow::tr("Reading area"));
    }
    int margin() const { return std::clamp(width() / 17, 22, 68); }
    int gutter() const { return std::clamp(width() / 18, 27, 59); }
    int top() const { return std::clamp(height() / 10, 24, 78); }
    QSize pageSize() const
    {
        const auto w = width() - 2 * margin();
        return {std::max(1, reader->spread() ? (w - gutter()) / 2 : std::min(w, 720)), std::max(1, height() - top() - 12)};
    }
protected:
    void resizeEvent(QResizeEvent *) override { reader->canvasResized(); }
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.setPen(ink);
        const auto &pages = reader->visiblePages();
        const auto current = reader->visibleIndex();
        if (!reader->document || pages.empty() || (reader->waiting && reader->preview.empty())) {
            p.setFont(readingFont(20, 0));
            const auto primary = reader->waiting ? ReaderWindow::tr("Preparing pages…") : reader->status.isEmpty() ? u"Good Text Viewer"_s : reader->status;
            p.drawText(rect().adjusted(25, 0, -25, -36), Qt::AlignCenter | Qt::TextWordWrap, primary);
            if (reader->status.isEmpty() && !reader->waiting) {
                p.setFont(font());
                p.drawText(rect().adjusted(25, 32, -25, 0), Qt::AlignCenter | Qt::TextWordWrap,
                    ReaderWindow::tr("Drop a TXT file here or click Open."));
            }
            return;
        }
        p.setRenderHint(QPainter::TextAntialiasing);
        const auto &[pageSize, font] = reader->currentLayout;
        const bool two = reader->spread();
        const auto x = (width() - (two ? 2 * pageSize.width() + gutter() : pageSize.width())) / 2.0;
        for (size_t column = 0; column < size_t(two ? 2 : 1); ++column) {
            if (current + column >= pages.size()) break;
            const auto at = QPointF(x + column * (pageSize.width() + gutter()), top());
            p.save();
            p.setClipRect(QRectF(at, pageSize));
            drawPage(p, at, reader->document->text, font, pages[current + column]);
            p.restore();
        }
    }
private:
    ReaderWindow *reader;
};

ReaderWindow::ReaderWindow(const QString &settingsFile) : preferences(settingsFile)
{
    auto &prefs = preferences.store();
    pageMode = prefs.value(u"pageMode"_s, 1).toInt() == 2 ? 2 : 1;
    fontSize = std::clamp(prefs.value(u"fontSize"_s, 18).toInt(), 12, 36);
    spacing = std::clamp(qRound(prefs.value(u"letterSpacing"_s, 0.0).toDouble() * 10), -5, 20);
    repair = activeRepair = prefs.value(u"repairsLegacyHardWraps"_s, true).toBool();
    setWindowTitle(u"Good Text Viewer"_s);
    setAcceptDrops(true);
#ifdef Q_OS_MACOS
    setAttribute(Qt::WA_ContentsMarginsRespectsSafeArea, false);
#endif
    workers.setMaxThreadCount(2);
    resizeTimer.setSingleShot(true);
    resizeTimer.setInterval(100);
    connect(&resizeTimer, &QTimer::timeout, this, &ReaderWindow::reflow);
    previewTimer.setSingleShot(true);
    previewTimer.setInterval(32);
    connect(&previewTimer, &QTimer::timeout, this, &ReaderWindow::startPreview);

    auto *surface = new QWidget(this);
#ifdef Q_OS_MACOS
    // Cover the native title-bar area with parchment. The title strip below
    // reserves its own leading inset for the system window buttons.
    surface->setAttribute(Qt::WA_ContentsMarginsRespectsSafeArea, false);
#endif
    surface->setObjectName(u"parchment"_s);
    surface->setStyleSheet(uR"(
        #parchment { background:#e6d3af; }
        QLabel { color:#392e22; }
        #rail { background:#efdfc2; border:1px solid #cbb592; border-radius:12px; }
        #railDivider { background:#cbb592; }
        QPushButton { color:#392e22; border:1px solid transparent; border-radius:7px; padding:4px; }
        QPushButton:hover { background:#dccaab; }
        QPushButton:checked { background:#a77547; color:#fff3d9; }
        QPushButton:focus { border-color:#a77547; }
        QPushButton:disabled { color:#998c78; }
        QPushButton[typeAdjustment="true"] { padding:1px; font-size:15px; font-weight:600; }
        QPushButton[typeAdjustment="true"]:pressed { background:#cdb491; }
        QPushButton[typeAdjustment="true"]:focus { border-color:#89603c; }
        QPushButton[typeAdjustment="true"]:disabled { background:transparent; }
        #filename { font-weight:600; }
    )"_s);
    setCentralWidget(surface);
    auto *main = new QVBoxLayout(surface);
    main->setContentsMargins(0, 0, 0, 7);
    main->setSpacing(0);
    auto *titleStrip = new TitleStrip(surface);
#ifdef Q_OS_MACOS
    titleStrip->setAttribute(Qt::WA_ContentsMarginsRespectsSafeArea, false);
#endif
    headerLayout = new QHBoxLayout(titleStrip);
    headerLayout->setContentsMargins(20, 7, 19, 8);
    fileName = new QLabel(u"Good Text Viewer"_s, titleStrip);
    fileName->setObjectName(u"filename"_s);
    fileName->setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
    fileName->setAttribute(Qt::WA_TransparentForMouseEvents);
    headerLayout->addWidget(fileName, 1);
    const auto openShortcut = QKeySequence(QKeySequence::Open).toString(QKeySequence::NativeText);
    auto *openButton = button(tr("%1  Open").arg(openShortcut), tr("Open a TXT file"), titleStrip);
    openButton->setFocusPolicy(Qt::TabFocus);
    headerLayout->addWidget(openButton);
    connect(openButton, &QPushButton::clicked, this, &ReaderWindow::chooseFile);
    main->addWidget(titleStrip);

    auto *divider = new QWidget(surface);
    divider->setFixedHeight(1);
    divider->setStyleSheet(u"background:#ebd9b7"_s);
    main->addWidget(divider);
    auto *body = new QHBoxLayout;
    body->setContentsMargins(0, 0, 16, 0);
    body->setSpacing(0);
    canvas = new ReaderCanvas(this);
    body->addWidget(canvas, 1);
    auto *rail = new QWidget(surface);
    rail->setObjectName(u"rail"_s);
    rail->setAttribute(Qt::WA_StyledBackground);
    rail->setFixedWidth(59);
    auto *railLayout = new QVBoxLayout(rail);
    railLayout->setContentsMargins(6, 7, 6, 7);
    railLayout->setSpacing(1);
    singleButton = button({}, tr("Single-page view"), rail);
    spreadButton = button({}, tr("Two-page view"), rail);
    singleButton->setIcon(bookIcon(false));
    spreadButton->setIcon(bookIcon(true));
    for (auto *b : {singleButton, spreadButton}) {
        b->setCheckable(true);
        b->setFixedHeight(33);
        railLayout->addWidget(b);
    }
    connect(singleButton, &QPushButton::clicked, this, [this] { setPageMode(1); });
    connect(spreadButton, &QPushButton::clicked, this, [this] { setPageMode(2); });
    const auto controls = [&](QPushButton *&more, QLabel *&value, QPushButton *&less,
                              TypeAdjustment adjustment, const QString &valueName, const QString &id,
                              const QString &moreName, const QString &lessName) {
        auto *separator = new QWidget(rail);
        separator->setObjectName(u"railDivider"_s);
        separator->setAttribute(Qt::WA_StyledBackground);
        separator->setFixedSize(29, 1);
        railLayout->addSpacing(5);
        railLayout->addWidget(separator, 0, Qt::AlignHCenter);
        railLayout->addSpacing(5);

        auto *icon = new QLabel(rail);
        icon->setPixmap(adjustmentIcon(adjustment));
        icon->setAlignment(Qt::AlignCenter);
        icon->setFixedHeight(20);
        icon->setToolTip(valueName);
        railLayout->addWidget(icon);
        value = new QLabel(rail);
        value->setAlignment(Qt::AlignCenter);
        value->setObjectName(id);
        value->setAccessibleName(valueName);
        value->setFixedHeight(22);
        auto number = value->font(); number.setPixelSize(15); number.setWeight(QFont::DemiBold); value->setFont(number);
        more = button(u"+"_s, moreName, rail);
        less = button(u"−"_s, lessName, rail);
        for (auto *b : {more, less}) {
            b->setProperty("typeAdjustment", true);
            b->setFixedHeight(25);
        }
        railLayout->addWidget(more);
        railLayout->addWidget(value);
        railLayout->addWidget(less);
    };
    controls(fontMore, fontValue, fontLess, TypeAdjustment::FontSize, tr("Font size"), u"fontValue"_s,
        tr("Increase font size"), tr("Decrease font size"));
    controls(spacingMore, spacingValue, spacingLess, TypeAdjustment::LetterSpacing, tr("Letter spacing"), u"spacingValue"_s,
        tr("Increase letter spacing"), tr("Decrease letter spacing"));
    connect(fontMore, &QPushButton::clicked, this, [this] { adjustFont(1); });
    connect(fontLess, &QPushButton::clicked, this, [this] { adjustFont(-1); });
    connect(spacingMore, &QPushButton::clicked, this, [this] { adjustSpacing(1); });
    connect(spacingLess, &QPushButton::clicked, this, [this] { adjustSpacing(-1); });
    body->addWidget(rail, 0, Qt::AlignVCenter);
    main->addLayout(body, 1);

    auto *bottomRow = new QHBoxLayout;
    auto *bottom = new QWidget(surface);
    bottom->setMaximumWidth(480);
    auto *footer = new QVBoxLayout(bottom);
    footer->setContentsMargins(7, 0, 7, 0);
    footer->setSpacing(1);
    auto *arrows = new QHBoxLayout;
    previous = button(u"‹"_s, tr("Previous page"), bottom);
    next = button(u"›"_s, tr("Next page"), bottom);
    previous->setFixedWidth(44);
    next->setFixedWidth(44);
    pagePosition = new QLabel(bottom);
    pagePosition->setAlignment(Qt::AlignCenter);
    pagePosition->setObjectName(u"pagePosition"_s);
    pagePosition->setFixedWidth(125);
    arrows->addStretch();
    arrows->addWidget(previous);
    arrows->addWidget(pagePosition);
    arrows->addWidget(next);
    arrows->addStretch();
    footer->addLayout(arrows);
    progress = new SeekBar(Qt::Horizontal, bottom);
    progress->setObjectName(u"progress"_s);
    progress->setAccessibleName(tr("Reading progress"));
    progress->setToolTip(tr("Click or drag to jump to a reading position"));
    progress->setRange(0, seekRange);
    progress->setSingleStep(100);
    progress->setPageStep(1000);
    progress->setFixedHeight(18);
    progress->setCursor(Qt::PointingHandCursor);
    footer->addWidget(progress);
    bottomRow->addStretch(1);
    bottomRow->addWidget(bottom, 8);
    bottomRow->addStretch(1);
    main->addLayout(bottomRow);
    connect(previous, &QPushButton::clicked, this, [this] { step(-1); });
    connect(next, &QPushButton::clicked, this, [this] { step(1); });
    connect(progress, &QSlider::valueChanged, this, [this](int value) { seek(value); });
    connect(progress, &QSlider::sliderReleased, this, [this] { refresh(); });

    auto *fileMenu = menuBar()->addMenu(tr("File"));
    fileMenu->addAction(tr("Open…"), QKeySequence::Open, this, &ReaderWindow::chooseFile);
    auto *recentMenu = fileMenu->addMenu(tr("Open Recent"));
    recentMenu->setObjectName(u"recentFiles"_s);
    recentMenu->setToolTipsVisible(true);
    connect(fileMenu, &QMenu::aboutToShow, this, [this, recentMenu] {
        recentMenu->clear();
        for (const auto &path : preferences.recentFiles()) {
            auto name = QFileInfo(path).fileName();
            auto *action = recentMenu->addAction(name.replace(u"&"_s, u"&&"_s), this, [this, path] { open(path); });
            action->setToolTip(QDir::toNativeSeparators(path));
        }
        if (recentMenu->isEmpty()) recentMenu->addAction(tr("No recent files"))->setEnabled(false);
    });
    fileMenu->addAction(tr("Close window"), QKeySequence::Close, this, &QWidget::close);
    auto *viewMenu = menuBar()->addMenu(tr("View"));
    viewMenu->addAction(tr("Single-page view"), QKeySequence(Qt::CTRL | Qt::Key_1), this, [this] { setPageMode(1); });
    viewMenu->addAction(tr("Two-page view"), QKeySequence(Qt::CTRL | Qt::Key_2), this, [this] { setPageMode(2); });
    viewMenu->addSeparator();
    auto *increase = viewMenu->addAction(tr("Increase font size"), QKeySequence::ZoomIn, this, [this] { adjustFont(1); });
    increase->setShortcuts({QKeySequence(Qt::CTRL | Qt::Key_Plus), QKeySequence(Qt::CTRL | Qt::Key_Equal)});
    viewMenu->addAction(tr("Decrease font size"), QKeySequence::ZoomOut, this, [this] { adjustFont(-1); });
    viewMenu->addAction(tr("Increase letter spacing"), QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_BracketRight), this, [this] { adjustSpacing(1); });
    viewMenu->addAction(tr("Decrease letter spacing"), QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_BracketLeft), this, [this] { adjustSpacing(-1); });
    viewMenu->addSeparator();
    repairAction = viewMenu->addAction(tr("Clean up hard line breaks"));
    repairAction->setCheckable(true);
    repairAction->setChecked(repair);
    connect(repairAction, &QAction::toggled, this, &ReaderWindow::setRepair);
    auto *navigation = menuBar()->addMenu(tr("Go"));
    navigation->addAction(tr("Previous page"), this, [this] { step(-1); });
    navigation->addAction(tr("Next page"), this, [this] { step(1); });
    auto *window = menuBar()->addMenu(tr("Window"));
    window->addAction(tr("Minimize"), QKeySequence(Qt::CTRL | Qt::Key_M), this, &QWidget::showMinimized);
    window->addAction(tr("Zoom"), this, [this] { isMaximized() ? showNormal() : showMaximized(); });
    auto *help = menuBar()->addMenu(tr("Help"));
    auto *about = help->addAction(tr("About Good Text Viewer"), this, [this] {
        QMessageBox::about(this, tr("About Good Text Viewer"),
            tr("<h3>Good Text Viewer</h3><p>Version %1 · Dev Dot.</p><p>Plain-text reader · MIT License</p><p>Qt %2</p>").arg(QString::fromLatin1(READER_VERSION), QString::fromLatin1(qVersion())));
    });
    about->setMenuRole(QAction::AboutRole);
#ifdef Q_OS_WIN
    auto *menuStyle = new CompactMenuStyle(menuBar()->style()->name());
    menuStyle->setParent(this);
    menuBar()->setStyle(menuStyle);
    for (auto *menu : {fileMenu, recentMenu, viewMenu, navigation, window, help}) menu->setStyle(menuStyle);
#endif
    const auto shortcut = [this](QKeySequence keys, auto f) { new QShortcut(keys, this, f); };
    for (auto key : {Qt::Key_Right, Qt::Key_Down, Qt::Key_PageDown, Qt::Key_Space})
        shortcut(QKeySequence(key), [this] { step(1); });
    for (auto key : {Qt::Key_Left, Qt::Key_Up, Qt::Key_PageUp})
        shortcut(QKeySequence(key), [this] { step(-1); });
    shortcut(QKeySequence(Qt::SHIFT | Qt::Key_Space), [this] { step(-1); });
    shortcut(QKeySequence(Qt::Key_Home), [this] { seek(0); });
    shortcut(QKeySequence(Qt::Key_End), [this] { seek(seekRange); });

    setMinimumSize(520, 475);
    resize(1120, 820);
    restoreGeometry(prefs.value(u"windowGeometry"_s).toByteArray());
    refresh();
}

ReaderWindow::~ReaderWindow()
{
    savePosition();
    cancel(loadToken);
    cancel(layoutToken);
    cancel(previewToken);
    workers.clear();
    workers.waitForDone();
}

void ReaderWindow::cancel(Cancel &token)
{
    if (token) token->store(true, std::memory_order_relaxed);
    token.reset();
}

bool ReaderWindow::spread() const { return pageMode == 2; }
const Pages &ReaderWindow::visiblePages() const { return preview.empty() ? pages : preview; }
size_t ReaderWindow::visibleIndex() const { return preview.empty() ? current : previewIndex; }

void ReaderWindow::dragEnterEvent(QDragEnterEvent *e) { if (!dropPath(e->mimeData()).isEmpty()) e->acceptProposedAction(); }
void ReaderWindow::dropEvent(QDropEvent *e)
{
    const auto path = dropPath(e->mimeData());
    if (!path.isEmpty()) { open(path); e->acceptProposedAction(); }
}
void ReaderWindow::closeEvent(QCloseEvent *e)
{
    savePosition();
    preferences.store().setValue(u"windowGeometry"_s, saveGeometry());
    QMainWindow::closeEvent(e);
}

void ReaderWindow::showEvent(QShowEvent *event)
{
    QMainWindow::showEvent(event);
    updateTitleBar();
#ifdef Q_OS_MACOS
    QTimer::singleShot(0, this, &ReaderWindow::updateTitleBar);
#endif
}

void ReaderWindow::changeEvent(QEvent *event)
{
    QMainWindow::changeEvent(event);
#ifdef Q_OS_MACOS
    if (event->type() == QEvent::WindowStateChange && isVisible())
        QTimer::singleShot(0, this, &ReaderWindow::updateTitleBar);
#endif
}

void ReaderWindow::updateTitleBar()
{
#ifdef Q_OS_MACOS
    if (QGuiApplication::platformName() != u"cocoa"_s) return;
    if (!unifiedTitleAndToolBarOnMac()) setUnifiedTitleAndToolBarOnMac(true);
    const int inset = useParchmentTitleBar(*this);
    if (inset > 20) {
        headerLayout->parentWidget()->setFixedHeight(54);
        headerLayout->setContentsMargins(inset, 3, 23, 8);
    }
#endif
}

void ReaderWindow::restoreLastFile()
{
    const auto path = preferences.store().value(u"lastDocumentPath"_s).toString();
    if (!path.isEmpty() && QFileInfo::exists(path)) open(path);
}

void ReaderWindow::chooseFile()
{
    const auto dir = document ? QFileInfo(document->path).absolutePath() : QString{};
    const auto selected = QFileDialog::getOpenFileName(this, tr("Open TXT File"), dir, tr("Text files (*.txt *.TXT)"));
    if (!selected.isEmpty()) open(selected);
}

void ReaderWindow::open(const QString &path) { savePosition(); startLoad(path); }

void ReaderWindow::startLoad(const QString &path, std::optional<double> oldFraction)
{
    cancel(loadToken);
    const auto token = loadToken = std::make_shared<std::atomic_bool>();
    const auto mode = repair;
    loadingPath = path;
    status = tr("Opening…");
    refresh();
    workers.start([this, path, mode, token, oldFraction] {
        auto result = load(path, mode, token);
        if (cancelled(token)) return;
        QMetaObject::invokeMethod(this, [this, result = std::move(result), token, mode, oldFraction] {
            if (token != loadToken || cancelled(token)) return;
            loadingPath.clear();
            status = result.error;
            if (!result.document) {
                if (repair != activeRepair && document) {
                    const QSignalBlocker blocker(repairAction);
                    repair = activeRepair;
                    repairAction->setChecked(repair);
                    preferences.store().setValue(u"repairsLegacyHardWraps"_s, repair);
                }
                refresh();
                emit loadFailed(result.error);
                return;
            }
            document = result.document;
            activeRepair = mode;
            pages.clear();
            preview.clear();
            current = 0;
            complete = waiting = pendingForward = false;
            pendingAnchor = oldFraction ? qsizetype(*oldFraction * document->text.size()) : preferences.anchor(*document, mode);
            savePosition();
            reflow();
        }, Qt::QueuedConnection);
    });
}

void ReaderWindow::savePosition()
{
    if (!document || (!pendingAnchor && pages.empty())) return;
    preferences.remember(*document, activeRepair, pendingAnchor.value_or(pages.empty() ? 0 : pages[current].start));
}

void ReaderWindow::setPageMode(int value)
{
    if (pageMode == value) { refresh(); return; }
    pageMode = value;
    preferences.store().setValue(u"pageMode"_s, value);
    reflow();
}
void ReaderWindow::adjustFont(int delta)
{
    fontSize = std::clamp(fontSize + delta, 12, 36);
    preferences.store().setValue(u"fontSize"_s, fontSize);
    reflow();
}
void ReaderWindow::adjustSpacing(int delta)
{
    spacing = std::clamp(spacing + delta, -5, 20);
    preferences.store().setValue(u"letterSpacing"_s, spacing / 10.0);
    reflow();
}
void ReaderWindow::setRepair(bool enabled)
{
    if (repair == enabled) return;
    savePosition();
    repair = enabled;
    preferences.store().setValue(u"repairsLegacyHardWraps"_s, repair);
    if (!loadingPath.isEmpty() && (!document || loadingPath != document->path)) {
        startLoad(loadingPath);
    } else if (document) {
        const auto at = pendingAnchor.value_or(pages.empty() ? 0 : pages[current].start);
        startLoad(document->path, std::clamp(at / double(std::max<qsizetype>(1, document->text.size())), 0.0, 1.0));
    }
}

void ReaderWindow::canvasResized() { if (document) resizeTimer.start(); }

void ReaderWindow::reflow()
{
    if (!document) { refresh(); return; }
    const Layout layout{canvas->pageSize(), readingFont(fontSize, spacing)};
    if (!pages.empty() && layout == currentLayout) { refresh(); return; }
    pendingAnchor = pendingAnchor.value_or(pages.empty() ? 0 : pages[current].start);
    currentLayout = layout;
    pages.clear();
    preview.clear();
    cancel(previewToken);
    previewTimer.stop();
    current = 0;
    complete = pendingForward = false;
    waiting = true;
    cancel(layoutToken);
    const auto token = layoutToken = std::make_shared<std::atomic_bool>();
    const auto doc = document;
    refresh();
    workers.start([this, token, doc, layout] {
        paginate(doc->text, layout, token, [this, token](Pages &&batch, bool done) {
            QMetaObject::invokeMethod(this, [this, token, batch = std::move(batch), done]() mutable {
                if (layoutToken != token || cancelled(token)) return;
                const auto old = current;
                const auto oldCount = pages.size();
                std::move(batch.begin(), batch.end(), std::back_inserter(pages));
                complete = done;
                reposition();
                if (pendingForward && current + size_t(pageMode) < pages.size()) {
                    pendingForward = false;
                    current += pageMode;
                }
                if (old != current || !oldCount || (spread() && oldCount <= current + 1) || done) {
                    refresh();
                    if (!pages.empty() && !waiting && (old != current || !oldCount || (spread() && oldCount <= current + 1))) emit pageShown(pages[current].start);
                }
                if (done) emit layoutFinished(qsizetype(pages.size()));
            }, Qt::QueuedConnection);
        });
    });
    if (*pendingAnchor) previewTimer.start();
}

void ReaderWindow::reposition()
{
    if (!pendingAnchor || pages.empty()) return;
    if (!complete && *pendingAnchor >= pages.back().end) return;
    const auto page = pageAt(pages, *pendingAnchor);
    current = page / size_t(pageMode) * size_t(pageMode);
    pendingAnchor.reset();
    previewTimer.stop();
    cancel(previewToken);
    preview.clear();
    waiting = false;
}

void ReaderWindow::step(int direction)
{
    if (!preview.empty()) {
        const auto at = preview[previewIndex].start;
        const auto extent = preview[std::min(preview.size() - 1, previewIndex + size_t(pageMode - 1))].end;
        if ((direction > 0 && extent < document->text.size()) || (direction < 0 && at > 0))
            requestAnchor(direction > 0 ? extent : std::max<qsizetype>(0, at - std::max<qsizetype>(1, (extent - at) * 3 / 4)));
        return;
    }
    if (pages.empty() || waiting) return;
    pendingAnchor.reset();
    previewTimer.stop();
    cancel(previewToken);
    pendingForward = false;
    const auto distance = size_t(pageMode);
    if (direction < 0) current = current >= distance ? current - distance : 0;
    else if (current + distance < pages.size()) current += distance;
    else pendingForward = !complete;
    refresh();
    savePosition();
    emit pageShown(pages[current].start);
}

void ReaderWindow::seek(int value)
{
    if (!document || document->text.isEmpty()) return;
    requestAnchor(qsizetype(std::llround(document->text.size() * (value / double(seekRange)))));
}

void ReaderWindow::requestAnchor(qsizetype where)
{
    const auto old = current;
    pendingForward = false;
    pendingAnchor = where;
    reposition();
    if (pendingAnchor) {
        cancel(previewToken);
        previewTimer.start();
    }
    refresh();
    if (old != current && !pages.empty()) emit pageShown(pages[current].start);
}

void ReaderWindow::startPreview()
{
    if (!document || !pendingAnchor || complete) return;
    const auto doc = document;
    const auto layout = currentLayout;
    const auto where = *pendingAnchor;
    const auto token = previewToken = std::make_shared<std::atomic_bool>();
    const auto extent = std::clamp<qsizetype>(pages.empty() ? 2500 : pages.front().end * 3, 2500, 12000);
    const auto mode = size_t(pageMode);
    // Seek ahead of the sequential index by shaping a small neighborhood. The
    // normal page boundaries take over once the index reaches this position.
    workers.start([this, doc, layout, token, where, extent, mode] {
        if (cancelled(token)) return;
        const QStringView text(doc->text);
        auto start = std::max<qsizetype>(0, where - extent);
        while (start > 0 && where - start < extent + 1024 && text[start - 1] != u'\n' && text[start - 1] != u'\r') --start;
        if (start < text.size() && text[start].isLowSurrogate()) ++start;
        if (start && start < text.size() && text[start - 1] == u'\r' && text[start] == u'\n') ++start;
        auto end = std::min(text.size(), where + extent);
        if (end < text.size() && text[end].isLowSurrogate()) --end;
        Pages local;
        paginate(text.sliced(start, end - start).toString(), layout, token, [&](Pages &&batch, bool) {
            for (auto &page : batch) {
                page.start += start;
                page.end += start;
                for (auto &line : page.lines) line.start += start;
            }
            std::move(batch.begin(), batch.end(), std::back_inserter(local));
        });
        if (cancelled(token) || local.empty()) return;
        const auto at = pageAt(local, where) / mode * mode;
        QMetaObject::invokeMethod(this, [this, token, layout, local = std::move(local), at]() mutable {
            if (token != previewToken || cancelled(token) || !pendingAnchor || currentLayout != layout) return;
            preview = std::move(local);
            previewIndex = at;
            refresh();
            emit pageShown(preview[at].start);
        }, Qt::QueuedConnection);
    }, -1);
}

void ReaderWindow::refresh()
{
    const auto title = document ? QFileInfo(document->path).fileName() : u"Good Text Viewer"_s;
    fileName->setText(loadingPath.isEmpty() ? title : tr("%1 · Opening…").arg(QFileInfo(loadingPath).fileName()));
    fileName->setToolTip(status.isEmpty() ? title : status);
    fontValue->setText(QString::number(fontSize));
    spacingValue->setText(QString::number(spacing / 10.0, 'f', 1));
    singleButton->setChecked(!spread());
    spreadButton->setChecked(spread());
    fontLess->setEnabled(fontSize > 12);
    fontMore->setEnabled(fontSize < 36);
    spacingLess->setEnabled(spacing > -5);
    spacingMore->setEnabled(spacing < 20);
    const auto &visible = visiblePages();
    const auto pos = visibleIndex();
    const bool ready = document && !visible.empty() && (!waiting || !preview.empty());
    const auto distance = size_t(pageMode);
    previous->setEnabled(ready && visible[pos].start > 0);
    next->setEnabled(ready && (preview.empty() ? current + distance < pages.size() || !complete :
        visible[std::min(visible.size() - 1, pos + distance - 1)].end < document->text.size()));
    progress->setEnabled(document && !document->text.isEmpty());
    const bool end = ready && complete && current + distance >= pages.size() && (current || !document->text.isEmpty());
    const auto anchor = pendingAnchor.value_or(!ready ? 0 : end ? document->text.size() : visible[pos].start);
    const int value = document && !document->text.isEmpty() ? qRound(anchor * double(seekRange) / document->text.size()) : 0;
    QString position = u"—"_s;
    if (!status.isEmpty() && !document) {
        position = status;
    } else if (!status.isEmpty() && loadingPath.isEmpty()) {
        position = tr("Couldn't open file");
    } else if (document) {
        const auto number = ready && preview.empty() ? QString::number(qulonglong(current / distance + 1)) : u"…"_s;
        const auto total = complete ? QString::number(qulonglong((pages.size() + distance - 1) / distance)) : u"…"_s;
        position = u"%1 / %2"_s.arg(number, total);
    }
    pagePosition->setText(position);
    pagePosition->setToolTip(status);
    if (!progress->isSliderDown()) {
        const QSignalBlocker blocker(progress);
        progress->setValue(value);
    }
    if (ready) {
        const auto last = std::min(visible.size() - 1, pos + distance - 1);
        canvas->setAccessibleDescription(document->text.sliced(visible[pos].start, visible[last].end - visible[pos].start));
    } else {
        canvas->setAccessibleDescription(status);
    }
    canvas->update();
}

} // namespace reader
