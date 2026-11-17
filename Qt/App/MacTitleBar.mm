#include "MacTitleBar.h"

#include <QGuiApplication>
#include <QWidget>
#include <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>

namespace reader {
namespace {
NSView *cocoaView(QWidget &widget)
{
    if (QGuiApplication::platformName() != QStringLiteral("cocoa")) return nil;
    return reinterpret_cast<NSView *>(widget.winId());
}
}

int useParchmentTitleBar(QWidget &widget)
{
    NSView *view = cocoaView(widget);
    NSWindow *window = view.window;
    if (!window) return 20;

    if (!(window.styleMask & NSWindowStyleMaskFullSizeContentView))
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.backgroundColor = [NSColor colorWithSRGBRed:230./255. green:211./255. blue:175./255. alpha:1.];
    window.movableByWindowBackground = NO;

    NSButton *zoom = [window standardWindowButton:NSWindowZoomButton];
    return zoom && !zoom.hidden
        ? std::max(84, int(std::ceil(NSMaxX([zoom.superview convertRect:zoom.frame toView:view]))) + 14)
        : 84;
}

bool dragFromTitleBar(QWidget &widget)
{
    NSWindow *window = cocoaView(widget).window;
    NSEvent *event = NSApp.currentEvent;
    if (!window || event.type != NSEventTypeLeftMouseDown || event.window != window) return false;
    [window performWindowDragWithEvent:event];
    return true;
}

} // namespace reader
