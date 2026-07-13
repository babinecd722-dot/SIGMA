cmake_minimum_required(VERSION 3.22)
project(resolution LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

add_library(resolution SHARED
  src/main.cpp
  src/hooks/hooks.cpp
  src/hooks/plthook.cpp
  src/util/log.cpp
  src/util/memory.cpp
  src/util/pattern.cpp
  src/game/game.cpp
  src/game/structures.cpp
  src/game/player.cpp
  src/game/camera.cpp
  src/game/radar.cpp
  src/features/esp.cpp
  src/features/aim.cpp
  src/features/teleport.cpp
  src/features/config.cpp
  src/ui/menu.cpp
  src/ui/fab.cpp
  src/ui/theme.cpp
  src/render/renderer.cpp
  src/render/imgui_impl_opengl3.cpp
  third_party/imgui/imgui.cpp
  third_party/imgui/imgui_draw.cpp
  third_party/imgui/imgui_tables.cpp
  third_party/imgui/imgui_widgets.cpp
)

target_include_directories(resolution PRIVATE
  src
  src/render
  third_party/imgui
  third_party/imgui/backends
)

target_compile_options(resolution PRIVATE
  -fno-rtti
  -fno-exceptions
  -ffunction-sections
  -fdata-sections
  -O2
  -Wall
  -Wextra
  -Wno-unused-parameter
)

target_link_options(resolution PRIVATE
  -Wl,--gc-sections
  -Wl,-z,max-page-size=16384
)

find_library(log-lib log)
find_library(android-lib android)
find_library(EGL-lib EGL)
find_library(GLESv3-lib GLESv3)
find_library(dl-lib dl)

target_link_libraries(resolution PRIVATE
  ${log-lib}
  ${android-lib}
  ${EGL-lib}
  ${GLESv3-lib}
  ${dl-lib}
)

target_compile_definitions(resolution PRIVATE
  IMGUI_IMPL_OPENGL_ES3
  IMGUI_DISABLE_OBSOLETE_FUNCTIONS
)
EOF