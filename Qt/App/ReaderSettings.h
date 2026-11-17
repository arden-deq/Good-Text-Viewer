#pragma once

#include "TextDocument.h"

#include <QSettings>

namespace reader {

class ReaderSettings {
public:
    explicit ReaderSettings(const QString &testFile = {});
    QSettings &store() { return *settings; }
    qsizetype anchor(const Document &doc, bool repair) const;
    void remember(const Document &doc, bool repair, qsizetype anchor);
private:
    std::unique_ptr<QSettings> settings;
};

} // namespace reader
