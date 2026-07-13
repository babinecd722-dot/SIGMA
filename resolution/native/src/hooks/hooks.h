#pragma once

#include <cstdint>

namespace res::hooks {

bool Install();
void Remove();

// Feed touch into ImGui from JNI / hooked input.
void OnTouch(int action, float x, float y, int pointer_id);

}  // namespace res::hooks
