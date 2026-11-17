#include "ReaderSettings.h"

#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>

#include <algorithm>

#ifdef Q_OS_MACOS
#include <CoreFoundation/CoreFoundation.h>
#endif

using namespace Qt::StringLiterals;

namespace reader {
namespace {

const auto positionsKey = u"readingPositions.v1"_s;

#ifdef Q_OS_MACOS
void migrate(QSettings &settings)
{
    if (settings.value(u"swiftPreferencesChecked"_s).toBool()) return;
    const auto domain = CFSTR("com.devdot.goodtextviewer");
    const auto read = [&](CFStringRef key, const QString &target) {
        if (settings.contains(target)) return;
        auto v = CFPreferencesCopyAppValue(key, domain);
        if (!v) return;
        if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            double n = 0;
            if (CFNumberGetValue(static_cast<CFNumberRef>(v), kCFNumberDoubleType, &n)) settings.setValue(target, n);
        } else if (CFGetTypeID(v) == CFBooleanGetTypeID()) {
            settings.setValue(target, CFBooleanGetValue(static_cast<CFBooleanRef>(v)));
        } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
            settings.setValue(target, QString::fromCFString(static_cast<CFStringRef>(v)));
        } else if (CFGetTypeID(v) == CFDataGetTypeID()) {
            const auto d = static_cast<CFDataRef>(v);
            settings.setValue(target, QByteArray(reinterpret_cast<const char *>(CFDataGetBytePtr(d)), CFDataGetLength(d)));
        }
        CFRelease(v);
    };
    read(CFSTR("fontSize"), u"fontSize"_s);
    read(CFSTR("letterSpacing"), u"letterSpacing"_s);
    read(CFSTR("pageMode"), u"pageMode"_s);
    read(CFSTR("repairsLegacyHardWraps"), u"repairsLegacyHardWraps"_s);
    read(CFSTR("lastDocumentPath"), u"lastDocumentPath"_s);
    read(CFSTR("readingPositions.v1"), positionsKey);
    settings.setValue(u"swiftPreferencesChecked"_s, true);
}
#endif

bool sameSlot(const QJsonObject &record, const Document &doc, bool repair)
{
    auto path = record.value(u"path"_s).toString();
    if (path.isEmpty()) return false;
#ifdef Q_OS_MACOS
    path = path.normalized(QString::NormalizationForm_C);
    return path == doc.path.normalized(QString::NormalizationForm_C) && record.value(u"repairsLegacyHardWraps"_s).toBool(true) == repair;
#else
    return path == doc.path && record.value(u"repairsLegacyHardWraps"_s).toBool(true) == repair;
#endif
}

} // namespace

ReaderSettings::ReaderSettings(const QString &testFile)
{
    if (!testFile.isEmpty()) {
        settings = std::make_unique<QSettings>(testFile, QSettings::IniFormat);
    } else {
        settings = std::make_unique<QSettings>(QSettings::NativeFormat, QSettings::UserScope, u"Dev Dot"_s, u"Good Text Viewer"_s);
#ifdef Q_OS_MACOS
        migrate(*settings);
#endif
    }
}

QStringList ReaderSettings::recentFiles() const
{
    const auto entries = QJsonDocument::fromJson(settings->value(positionsKey).toByteArray()).array();
    QStringList files;
    QSet<QString> seen;
    for (auto i = entries.size(); i > 0 && files.size() < 10; --i) {
        const auto path = entries.at(i - 1).toObject().value(u"path"_s).toString();
        if (path.isEmpty()) continue;
#ifdef Q_OS_MACOS
        const auto key = path.normalized(QString::NormalizationForm_C);
#elif defined(Q_OS_WIN)
        const auto key = path.toCaseFolded();
#else
        const auto &key = path;
#endif
        if (seen.contains(key)) continue;
        seen.insert(key);
        files.append(path);
    }
    return files;
}

qsizetype ReaderSettings::anchor(const Document &doc, bool repair) const
{
    const auto entries = QJsonDocument::fromJson(settings->value(positionsKey).toByteArray()).array();
    for (const auto &entry : entries) {
        const auto record = entry.toObject();
        if (sameSlot(record, doc, repair) && record.value(u"fileSize"_s).toInteger() == doc.fileSize &&
            std::abs(record.value(u"modificationTime"_s).toDouble() * 1000 - doc.modifiedMs) < 1.01) {
            return std::clamp<qsizetype>(record.value(u"anchor"_s).toInteger(), 0, doc.text.size());
        }
    }
    return 0;
}

void ReaderSettings::remember(const Document &doc, bool repair, qsizetype anchor)
{
    auto entries = QJsonDocument::fromJson(settings->value(positionsKey).toByteArray()).array();
    for (auto i = entries.size(); i > 0; --i)
        if (sameSlot(entries.at(i - 1).toObject(), doc, repair)) entries.removeAt(i - 1);
    while (entries.size() >= 50) entries.removeFirst();
    entries.append(QJsonObject{{u"path"_s, doc.path}, {u"fileSize"_s, doc.fileSize},
        {u"modificationTime"_s, doc.modifiedMs / 1000.0}, {u"anchor"_s, qint64(anchor)},
        {u"repairsLegacyHardWraps"_s, repair}});
    settings->setValue(positionsKey, QJsonDocument(entries).toJson(QJsonDocument::Compact));
    settings->setValue(u"lastDocumentPath"_s, doc.path);
}

} // namespace reader
