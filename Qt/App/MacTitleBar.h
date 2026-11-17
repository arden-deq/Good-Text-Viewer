#pragma once

class QWidget;

namespace reader {

// Returns the left inset needed to keep the filename clear of the native buttons.
int useParchmentTitleBar(QWidget &widget);
bool dragFromTitleBar(QWidget &widget);

} // namespace reader
