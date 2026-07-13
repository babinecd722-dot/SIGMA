#pragma once

#include "imgui.h"

namespace res::ui {

void ApplyResolutionTheme();

inline constexpr ImVec4 kAccent = ImVec4(46 / 255.f, 230 / 255.f, 166 / 255.f, 1.f);
inline constexpr ImVec4 kBg = ImVec4(10 / 255.f, 12 / 255.f, 16 / 255.f, 0.94f);
inline constexpr ImVec4 kPanel = ImVec4(16 / 255.f, 18 / 255.f, 24 / 255.f, 0.98f);
inline constexpr ImVec4 kText = ImVec4(0.92f, 0.94f, 0.96f, 1.f);
inline constexpr ImVec4 kMuted = ImVec4(0.55f, 0.60f, 0.65f, 1.f);

}  // namespace res::ui
