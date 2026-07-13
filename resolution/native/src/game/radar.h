#pragma once

#include "game/structures.h"

namespace res::game::radar {

MarkerSnapshot CaptureMarker();
bool TeleportToMarker();
bool RefreshMapModel();

}  // namespace res::game::radar
