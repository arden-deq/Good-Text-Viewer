#pragma once

#include "TextDocument.h"

#include <QSettings>
#include <QStringList>

namespace reader {

class ReaderSettings {
public:
    explicit ReaderSettings(const QString &testFile = {});
    QSettings &store() { return *settings; }
    QStringList recentFiles() const;
    qsizetype anchor(const Document &doc, bool repair) const;
    void remember(const Document &doc, bool repair, qsizetype anchor);
private:
    std::unique_ptr<QSettings> settings;
};

} // namespace reader
