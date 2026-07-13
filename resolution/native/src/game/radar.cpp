#include "game/radar.h"

#include "game/br_offsets.h"
#include "game/game.h"
#include "game/player.h"
#include "util/log.h"
#include "util/memory.h"

namespace res::game::radar {
namespace {

bool ReadLocation(uintptr_t loc, MarkerSnapshot& out) {
  if (!loc) return false;
  uint8_t has = 0;
  if (!mem::Read(reinterpret_cast<void*>(loc + br::kLocHasPos), has) || !has) return false;
  Vec3 pos{};
  if (!mem::ReadBytes(reinterpret_cast<void*>(loc + br::kLocPos), &pos, sizeof(pos))) return false;
  out.valid = true;
  out.world = pos;
  out.is_gps = true;
  return true;
}

uintptr_t ActiveNavLocation(uintptr_t map_model) {
  if (!map_model) return 0;
  // Mirrors 0x15BE708: only +0x394 when mode byte == 1.
  uint8_t mode = 0;
  mem::Read(reinterpret_cast<void*>(map_model + br::kMapNavMode), mode);
  if (mode == 1) return map_model + br::kMapNavTarget;
  // Fallback: try primary GPS target anyway if HasPosition set.
  MarkerSnapshot tmp{};
  if (ReadLocation(map_model + br::kMapNavTarget, tmp)) return map_model + br::kMapNavTarget;
  if (ReadLocation(map_model + br::kMapNavAlt, tmp)) return map_model + br::kMapNavAlt;
  return 0;
}

}  // namespace

MarkerSnapshot CaptureMarker() {
  MarkerSnapshot m;
  uintptr_t map = detail::MapModel();
  if (!map) return m;
  uintptr_t loc = ActiveNavLocation(map);
  ReadLocation(loc, m);
  return m;
}

bool TeleportToMarker() {
  auto m = CaptureMarker();
  if (!m.valid) {
    RES_LOGW("no GPS navigation target (bind CMapModel / set map marker)");
    return false;
  }
  RES_LOGI("teleport -> marker (%.2f, %.2f, %.2f)", m.world.x, m.world.y, m.world.z);
  return player::SetPosition(m.world);
}

}  // namespace res::game::radar
EOF