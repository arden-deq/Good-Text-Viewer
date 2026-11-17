#pragma once

#include <QByteArrayView>
#include <QString>

#include <atomic>
#include <memory>

namespace reader {

using Cancel = std::shared_ptr<std::atomic_bool>;

inline bool cancelled(const Cancel &token)
{
    return token && token->load(std::memory_order_relaxed);
}

enum class Encoding { Utf8, Utf16LE, Utf16BE, Cp949 };

struct Document {
    QString path;
    QString text;
    qint64 fileSize = 0;
    qint64 modifiedMs = 0;
    Encoding encoding = Encoding::Utf8;
};

struct LoadResult {
    std::shared_ptr<const Document> document;
    QString error;
};

LoadResult decode(QByteArrayView bytes, bool repair = true, const Cancel &cancel = {});
LoadResult load(const QString &path, bool repair = true, const Cancel &cancel = {});
QString repairLegacyWraps(const QString &source, const Cancel &cancel = {});

} // namespace reader
