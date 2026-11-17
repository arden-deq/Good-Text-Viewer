#pragma once

#include "Pagination.h"
#include "ReaderSettings.h"

#include <QMainWindow>
#include <QThreadPool>
#include <QTimer>

#include <optional>

class QAction;
class QLabel;
class QPushButton;
class QSlider;
class QHBoxLayout;

namespace reader {

class ReaderCanvas;

class ReaderWindow final : public QMainWindow {
    Q_OBJECT
public:
    explicit ReaderWindow(const QString &settingsFile = {});
    ~ReaderWindow() override;
    void open(const QString &path);
    void restoreLastFile();
    void savePosition();

signals:
    void pageShown(qsizetype anchor);
    void layoutFinished(qsizetype pages);
    void loadFailed(const QString &error);

protected:
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dropEvent(QDropEvent *event) override;
    void closeEvent(QCloseEvent *event) override;
    void showEvent(QShowEvent *event) override;
    void changeEvent(QEvent *event) override;

private:
    friend class ReaderCanvas;
    void chooseFile();
    void startLoad(const QString &path, std::optional<double> oldFraction = {});
    void setPageMode(int value);
    void adjustFont(int delta);
    void adjustSpacing(int delta);
    void setRepair(bool enabled);
    void reflow();
    void refresh();
    void reposition();
    void canvasResized();
    void updateTitleBar();
    void step(int direction);
    void seek(int value);
    void requestAnchor(qsizetype where);
    void startPreview();
    const Pages &visiblePages() const;
    size_t visibleIndex() const;
    bool spread() const;
    static void cancel(Cancel &token);

    ReaderSettings preferences;
    QThreadPool workers;
    QTimer resizeTimer, previewTimer;
    Cancel loadToken, layoutToken, previewToken;
    std::shared_ptr<const Document> document;
    Pages pages;
    Pages preview;
    Layout currentLayout;
    std::optional<qsizetype> pendingAnchor;
    size_t current = 0, previewIndex = 0;
    int pageMode = 1, fontSize = 18, spacing = 0;
    bool repair = true, activeRepair = true, complete = false, waiting = false, pendingForward = false;
    QString loadingPath, status;

    ReaderCanvas *canvas;
    QHBoxLayout *headerLayout;
    QLabel *fileName, *fontValue, *spacingValue, *pagePosition;
    QPushButton *singleButton, *spreadButton, *fontLess, *fontMore, *spacingLess, *spacingMore, *previous, *next;
    QSlider *progress;
    QAction *repairAction;
};

} // namespace reader
