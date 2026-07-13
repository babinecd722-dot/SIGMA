#pragma once

#include "game/structures.h"

namespace res::game::camera {

CameraSnapshot Capture();
bool WorldToScreen(const Vec3& world, Vec2& out);

}  // namespace res::game::camera
EOF