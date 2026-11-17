cmake_minimum_required(VERSION 3.24)
project(GoodTextViewer VERSION 1.2.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(MSVC)
    add_compile_options(/utf-8)
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Widgets LinguistTools)
if(APPLE AND TARGET WrapOpenGL::WrapOpenGL)
    # Qt 6.8.3's CMake helper adds the obsolete AGL framework even when
    # the macOS 26 SDK no longer ships it. The 64-bit Qt binaries don't use it.
    get_target_property(qt_gl_links WrapOpenGL::WrapOpenGL INTERFACE_LINK_LIBRARIES)
    if(qt_gl_links)
        list(FILTER qt_gl_links EXCLUDE REGEX "(^|/| )AGL([.]framework)?$")
        set_property(TARGET WrapOpenGL::WrapOpenGL PROPERTY INTERFACE_LINK_LIBRARIES "${qt_gl_links}")
    endif()
endif()
qt_standard_project_setup()
include(CTest)

add_library(reader_core STATIC
    Qt/Core/TextDocument.cpp
    Qt/Core/LegacyWrap.cpp
    Qt/Core/Pagination.cpp
)
target_include_directories(reader_core PUBLIC Qt/Core)
target_link_libraries(reader_core PUBLIC Qt6::Gui)
if(NOT WIN32)
    find_package(Iconv REQUIRED)
    target_link_libraries(reader_core PRIVATE Iconv::Iconv)
endif()

qt_add_executable(GoodTextViewer WIN32 MACOSX_BUNDLE
    Qt/App/Main.cpp
    Qt/App/ReaderWindow.cpp
    Qt/App/ReaderWindow.h
    Qt/App/ReaderSettings.cpp
)
target_link_libraries(GoodTextViewer PRIVATE reader_core Qt6::Widgets)
target_compile_definitions(GoodTextViewer PRIVATE READER_VERSION="${PROJECT_VERSION}")
qt_add_resources(GoodTextViewer app_icon PREFIX "/" FILES Assets/AppIcon-1024-final.png)
if(APPLE)
    enable_language(OBJCXX)
    set(CMAKE_OBJCXX_STANDARD 20)
    set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
    find_library(CORE_FOUNDATION CoreFoundation REQUIRED)
    target_link_libraries(GoodTextViewer PRIVATE "${CORE_FOUNDATION}")
    target_sources(GoodTextViewer PRIVATE Qt/App/MacTitleBar.mm)
    target_sources(GoodTextViewer PRIVATE Assets/AppIcon.icns)
    set_source_files_properties(Assets/AppIcon.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    set_target_properties(GoodTextViewer PROPERTIES MACOSX_BUNDLE_INFO_PLIST
        "${PROJECT_SOURCE_DIR}/Packaging/Info.plist")
    install(FILES LICENSE Packaging/ThirdPartyNotices.txt DESTINATION "GoodTextViewer.app/Contents/Resources")
    install(DIRECTORY Packaging/licenses/ DESTINATION "GoodTextViewer.app/Contents/Resources/licenses")
    install(FILES Assets/Fonts/OFL.txt DESTINATION "GoodTextViewer.app/Contents/Resources/licenses" RENAME Noto-Serif-KR-OFL.txt)
elseif(WIN32)
    enable_language(RC)
    set_property(TARGET GoodTextViewer PROPERTY qt_no_entrypoint TRUE)
    target_link_libraries(GoodTextViewer PRIVATE shell32)
    target_sources(GoodTextViewer PRIVATE Packaging/windows/GoodTextViewer.rc)
    target_include_directories(GoodTextViewer PRIVATE Assets)
    install(FILES LICENSE Packaging/ThirdPartyNotices.txt DESTINATION .)
    install(DIRECTORY Packaging/licenses/ DESTINATION licenses)
    install(FILES Assets/Fonts/OFL.txt DESTINATION licenses RENAME Noto-Serif-KR-OFL.txt)
endif()

install(TARGETS GoodTextViewer BUNDLE DESTINATION . RUNTIME DESTINATION .)
if(APPLE AND NOT CMAKE_CROSSCOMPILING)
    qt_generate_deploy_app_script(TARGET GoodTextViewer OUTPUT_SCRIPT deploy_reader NO_TRANSLATIONS)
    install(SCRIPT "${deploy_reader}")
endif()

if(BUILD_TESTING)
    find_package(Qt6 6.8 REQUIRED COMPONENTS Test)
    qt_add_executable(reader_tests
        Qt/Tests/ReaderTests.cpp
        Qt/App/ReaderWindow.cpp
        Qt/App/ReaderWindow.h
        Qt/App/ReaderSettings.cpp
    )
    target_link_libraries(reader_tests PRIVATE reader_core Qt6::Widgets Qt6::Test)
    if(APPLE)
        target_sources(reader_tests PRIVATE Qt/App/MacTitleBar.mm)
        target_link_libraries(reader_tests PRIVATE "${CORE_FOUNDATION}")
    endif()
    target_compile_definitions(reader_tests PRIVATE READER_VERSION="${PROJECT_VERSION}")
    target_compile_definitions(reader_tests PRIVATE READER_SAMPLES="${PROJECT_SOURCE_DIR}/Samples")
    add_test(NAME ReaderTests COMMAND reader_tests)
    set_tests_properties(ReaderTests PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    if(APPLE OR WIN32)
        add_test(NAME ReaderNativeFont COMMAND reader_tests bundledReadingFont)
        if(APPLE)
            set_tests_properties(ReaderNativeFont PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=cocoa")
        else()
            set_tests_properties(ReaderNativeFont PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=windows")
        endif()
    endif()
endif()

set(reader_targets GoodTextViewer)
if(BUILD_TESTING)
    list(APPEND reader_targets reader_tests)
endif()
if(APPLE OR WIN32)
    foreach(target IN LISTS reader_targets)
        qt_add_resources(${target} reading_font PREFIX "/" FILES Assets/Fonts/NotoSerifKR-Medium.ttf)
    endforeach()
endif()
qt_add_translations(TARGETS ${reader_targets}
    SOURCE_TARGETS GoodTextViewer reader_core
    TS_FILES "${CMAKE_CURRENT_SOURCE_DIR}/Qt/Translations/GoodTextViewer_ko.ts"
    RESOURCE_PREFIX "/i18n"
    NO_GENERATE_PLURALS_TS_FILE
)
