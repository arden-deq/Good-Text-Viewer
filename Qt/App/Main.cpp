#include "ReaderWindow.h"

#include <QApplication>
#include <QFileOpenEvent>
#include <QIcon>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <shellapi.h>
#include <vector>
#endif

using namespace Qt::StringLiterals;

class ReaderApplication final : public QApplication {
public:
    using QApplication::QApplication;
    reader::ReaderWindow *window = nullptr;
    QString pending;
protected:
    bool event(QEvent *event) override
    {
        if (event->type() == QEvent::FileOpen) {
            const auto path = static_cast<QFileOpenEvent *>(event)->file();
            if (!path.isEmpty()) {
                if (window) { window->open(path); window->show(); window->raise(); }
                else pending = path;
                return true;
            }
        }
        return QApplication::event(event);
    }
};

static int runApplication(int argc, char **argv)
{
    ReaderApplication app(argc, argv);
    app.setApplicationName(u"GoodTextViewer"_s);
    app.setApplicationDisplayName(u"Good Text Viewer"_s);
    app.setOrganizationName(u"Dev Dot."_s);
    app.setOrganizationDomain(u"devdot.com"_s);
    app.setApplicationVersion(QString::fromLatin1(READER_VERSION));
    app.setWindowIcon(QIcon(u":/Assets/AppIcon-1024-final.png"_s));
    app.setLayoutDirection(Qt::LeftToRight);
    reader::ReaderWindow window(qEnvironmentVariable("GTV_SETTINGS_FILE"));
    app.window = &window;
    window.show();
    const auto args = app.arguments();
    if (!app.pending.isEmpty()) window.open(app.pending);
    else if (args.size() > 1) window.open(args[1]);
    else window.restoreLastFile();
    const int code = app.exec();
    app.window = nullptr;
    return code;
}

#ifdef Q_OS_WIN
int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int)
{
    int argc = 0;
    auto **wide = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!wide) return 1;
    std::vector<QByteArray> encoded;
    encoded.reserve(argc);
    for (int i = 0; i < argc; ++i) encoded.push_back(QString::fromWCharArray(wide[i]).toUtf8());
    LocalFree(wide);
    std::vector<char *> argv;
    argv.reserve(argc + 1);
    for (auto &arg : encoded) argv.push_back(arg.data());
    argv.push_back(nullptr);
    return runApplication(argc, argv.data());
}
#else
int main(int argc, char **argv) { return runApplication(argc, argv); }
#endif
