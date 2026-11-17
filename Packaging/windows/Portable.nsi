Unicode true
Name "Good Text Viewer"
OutFile "${OUTPUT_EXE}"
RequestExecutionLevel user
SilentInstall silent
AutoCloseWindow true
SetCompressor /SOLID lzma
Icon "${APP_ICON}"

!include "FileFunc.nsh"

Section
    ${GetParameters} $0
    InitPluginsDir
    SetOutPath "$PLUGINSDIR"
    File /r "${SOURCE_DIR}\*"
    SetOutPath "$EXEDIR"
    ClearErrors
    ExecWait '"$PLUGINSDIR\GoodTextViewer.exe" $0' $1
    IfErrors 0 launched
    MessageBox MB_ICONSTOP "Good Text Viewer could not start."
    SetErrorLevel 1
    Quit
launched:
    SetErrorLevel $1
SectionEnd
