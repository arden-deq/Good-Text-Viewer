#include "TextDocument.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QStringConverter>
#include <QSysInfo>

#include <algorithm>
#include <limits>
#include <optional>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#else
#include <iconv.h>
#endif

using namespace Qt::StringLiterals;

namespace reader {
namespace {

constexpr qint64 maxFileSize = std::numeric_limits<int>::max();

bool looksBinary(QByteArrayView bytes)
{
    const auto sample = bytes.first(std::min<qsizetype>(bytes.size(), 16384));
    qsizetype controls = 0;
    for (const unsigned char ch : sample) {
        if (ch == 0)
            return true;
        controls += ch < 9 || (ch > 13 && ch < 32);
    }
    return controls * 100 > sample.size();
}

bool plausibleUnicode(QStringView value)
{
    qsizetype controls = 0;
    const auto sample = value.first(std::min<qsizetype>(value.size(), 4096));
    for (const QChar ch : sample) {
        const auto unit = ch.unicode();
        if (unit == 0)
            return false;
        controls += unit < 9 || (unit > 13 && unit < 32) || (unit >= 0x7f && unit <= 0x9f);
    }
    return sample.isEmpty() || controls * 100 < sample.size();
}

std::optional<QString> decodeUnicode(QByteArrayView bytes, QStringConverter::Encoding encoding)
{
    const bool utf16 = encoding == QStringConverter::Utf16LE || encoding == QStringConverter::Utf16BE;
    if (utf16 && bytes.size() % 2)
        return std::nullopt;
    QStringDecoder decoder(encoding, QStringConverter::Flag::Stateless);
    QString result = decoder(bytes);
    if (decoder.hasError() || (utf16 && !result.isValidUtf16()))
        return std::nullopt;
    return result;
}

std::optional<Encoding> utf16Signal(QByteArrayView bytes)
{
    if (bytes.size() < 4 || bytes.size() % 2)
        return std::nullopt;
    const auto limit = std::min<qsizetype>(8192, bytes.size());
    qsizetype evenZeros = 0, oddZeros = 0, beBreaks = 0, leBreaks = 0;
    for (qsizetype i = 0; i < limit; i += 2) {
        const char first = bytes[i];
        const char second = bytes[i + 1];
        evenZeros += first == 0;
        oddZeros += second == 0;
        beBreaks += first == 0 && (second == '\n' || second == '\r');
        leBreaks += second == 0 && (first == '\n' || first == '\r');
    }
    if (leBreaks != beBreaks)
        return leBreaks > beBreaks ? Encoding::Utf16LE : Encoding::Utf16BE;
    const auto signal = std::max<qsizetype>(2, limit / 100);
    if (oddZeros - evenZeros >= signal)
        return Encoding::Utf16LE;
    if (evenZeros - oddZeros >= signal)
        return Encoding::Utf16BE;
    return std::nullopt;
}

std::optional<QString> decodeCp949(QByteArrayView bytes)
{
#ifdef Q_OS_WIN
    if (bytes.size() > std::numeric_limits<int>::max())
        return std::nullopt;
    const auto size = int(bytes.size());
    const int count = MultiByteToWideChar(949, MB_ERR_INVALID_CHARS, bytes.data(), size, nullptr, 0);
    if (!count)
        return std::nullopt;
    QString result(count, Qt::Uninitialized);
    if (!MultiByteToWideChar(949, MB_ERR_INVALID_CHARS, bytes.data(), size,
                             reinterpret_cast<wchar_t *>(result.data()), count))
        return std::nullopt;
#else
    const auto outputEncoding = QSysInfo::ByteOrder == QSysInfo::LittleEndian ? "UTF-16LE" : "UTF-16BE";
    const auto converter = iconv_open(outputEncoding, "CP949");
    if (converter == reinterpret_cast<iconv_t>(-1))
        return std::nullopt;
    auto *input = const_cast<char *>(bytes.data()); // iconv advances the pointer without writing.
    size_t remaining = size_t(bytes.size());
    QString result(bytes.size(), Qt::Uninitialized);
    auto *output = reinterpret_cast<char *>(result.data());
    size_t available = size_t(result.size()) * sizeof(QChar);
    const auto status = iconv(converter, &input, &remaining, &output, &available);
    iconv_close(converter);
    if (status == size_t(-1) || remaining)
        return std::nullopt;
    result.resize(result.size() - qsizetype(available / sizeof(QChar)));
#endif
    return result;
}

LoadResult decodeInto(QByteArrayView bytes, std::shared_ptr<Document> document, bool repair,
                      const Cancel &cancel)
{
    if (cancelled(cancel))
        return {};
    auto encoding = Encoding::Utf8;
    std::optional<QString> decoded;
    if (bytes.startsWith("\xff\xfe") || bytes.startsWith("\xfe\xff")) {
        encoding = bytes[0] == char(0xff) ? Encoding::Utf16LE : Encoding::Utf16BE;
        decoded = decodeUnicode(bytes.sliced(2), encoding == Encoding::Utf16LE
                                    ? QStringConverter::Utf16LE : QStringConverter::Utf16BE);
    } else if (bytes.startsWith("\xef\xbb\xbf")) {
        decoded = decodeUnicode(bytes.sliced(3), QStringConverter::Utf8);
    } else {
        const bool binary = looksBinary(bytes);
        if (!binary) decoded = decodeUnicode(bytes, QStringConverter::Utf8);
        if (!decoded) {
            if (const auto detected = utf16Signal(bytes)) {
                encoding = *detected;
                decoded = decodeUnicode(bytes, encoding == Encoding::Utf16LE
                                            ? QStringConverter::Utf16LE : QStringConverter::Utf16BE);
                if (decoded && !plausibleUnicode(*decoded)) decoded.reset();
            }
        }
        if (binary && !decoded) return {{}, QCoreApplication::translate("TextDocument", "This file does not appear to contain plain text.")};
        if (!decoded) {
            encoding = Encoding::Cp949;
            decoded = decodeCp949(bytes);
        }
    }
    if (!decoded)
        return {{}, QCoreApplication::translate("TextDocument", "The file's text encoding is not supported.")};
    if (decoded->contains(QChar::Null))
        return {{}, QCoreApplication::translate("TextDocument", "This file does not appear to contain plain text.")};
    if (decoded->startsWith(QChar::ByteOrderMark))
        decoded->remove(0, 1);
    document->encoding = encoding;
    document->text = repair ? repairLegacyWraps(*decoded, cancel) : std::move(*decoded);
    if (cancelled(cancel))
        return {};
    return {std::move(document), {}};
}

} // namespace

LoadResult decode(QByteArrayView bytes, bool repair, const Cancel &cancel)
{
    return decodeInto(bytes, std::make_shared<Document>(), repair, cancel);
}

LoadResult load(const QString &path, bool repair, const Cancel &cancel)
{
    if (cancelled(cancel))
        return {};
    const QFileInfo info(path);
    if (info.suffix().compare(u"txt", Qt::CaseInsensitive))
        return {{}, QCoreApplication::translate("TextDocument", "Only TXT files can be opened.")};
    if (!info.isFile())
        return {{}, QCoreApplication::translate("TextDocument", "This is not a regular TXT file.")};
    QFile file(info.absoluteFilePath());
    if (!file.open(QIODevice::ReadOnly))
        return {{}, QCoreApplication::translate("TextDocument", "Could not read the file. Check that it is accessible.")};
    const auto size = file.size();
    if (size > maxFileSize)
        return {{}, QCoreApplication::translate("TextDocument", "TXT files must be smaller than 2 GiB.")};
    QByteArray bytes;
    bytes.reserve(qsizetype(size));
    while (!file.atEnd()) {
        if (cancelled(cancel))
            return {};
        bytes.append(file.read(1024 * 1024));
        if (file.error() != QFileDevice::NoError)
            return {{}, QCoreApplication::translate("TextDocument", "Could not read the file.")};
        if (bytes.size() > maxFileSize)
            return {{}, QCoreApplication::translate("TextDocument", "TXT files must be smaller than 2 GiB.")};
    }
    auto result = std::make_shared<Document>();
    result->path = info.absoluteFilePath();
    result->fileSize = bytes.size();
    result->modifiedMs = info.lastModified().toMSecsSinceEpoch();
    return decodeInto(bytes, std::move(result), repair, cancel);
}

} // namespace reader
