#include "game/radar.h"

#include "game/br_offsets.h"
#include "game/game.h"
#include "game/player.h"
#include "util/log.h"
#include "util/memory.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <string>

namespace res::game::radar {
namespace {

using Clock = std::chrono::steady_clock;

bool FiniteVec(const Vec3& v) {
  return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}

bool PlausibleWorld(const Vec3& v) {
  if (!FiniteVec(v)) return false;
  if (std::fabs(v.x) > 20000.f || std::fabs(v.y) > 20000.f) return false;
  if (v.z < -500.f || v.z > 5000.f) return false;
  return true;
}

bool ReadLocation(uintptr_t loc, MarkerSnapshot& out) {
  if (!loc) return false;
  uint8_t has = 0;
  if (!mem::Read(reinterpret_cast<void*>(loc + br::kLocHasPos), has) || !has) return false;
  Vec3 pos{};
  if (!mem::ReadBytes(reinterpret_cast<void*>(loc + br::kLocPos), &pos, sizeof(pos))) return false;
  if (!PlausibleWorld(pos)) return false;
  out.valid = true;
  out.world = pos;
  out.is_gps = true;
  return true;
}

bool LooksLikeMapModel(uintptr_t map, uintptr_t client_base) {
  if (!map || !client_base) return false;
  if ((map & 0x7) != 0) return false;
  uintptr_t sentinel = 0;
  if (!mem::Read(reinterpret_cast<void*>(map + br::kMapListSentinel), sentinel)) return false;
  if (sentinel != client_base + br::kMapListSentinelRva) return false;
  uint8_t mode = 0xFF;
  if (!mem::Read(reinterpret_cast<void*>(map + br::kMapNavMode), mode)) return false;
  if (mode > 4) return false;
  return true;
}

uintptr_t ActiveNavLocation(uintptr_t map_model) {
  if (!map_model) return 0;
  uint8_t mode = 0;
  mem::Read(reinterpret_cast<void*>(map_model + br::kMapNavMode), mode);
  if (mode == 1) {
    MarkerSnapshot tmp{};
    if (ReadLocation(map_model + br::kMapNavTarget, tmp)) return map_model + br::kMapNavTarget;
  }
  MarkerSnapshot tmp{};
  if (ReadLocation(map_model + br::kMapNavTarget, tmp)) return map_model + br::kMapNavTarget;
  if (ReadLocation(map_model + br::kMapNavAlt, tmp)) return map_model + br::kMapNavAlt;
  return 0;
}

uintptr_t ScanForMapModel() {
  const uintptr_t base = detail::Base();
  if (!base) return 0;

  uintptr_t best = 0;
  uintptr_t best_gps = 0;

  std::ifstream maps("/proc/self/maps");
  if (!maps) return 0;
  std::string line;
  while (std::getline(maps, line)) {
    uintptr_t a = 0, b = 0;
    char perms[8] = {};
    if (std::sscanf(line.c_str(), "%lx-%lx %7s", &a, &b, perms) != 3) continue;
    if (perms[0] != 'r' || perms[1] != 'w') continue;
    if (line.find(br::kClientSo) != std::string::npos) continue;
    // Prefer anonymous heap; skip file-backed mappings.
    if (!line.empty() && line.back() != ' ' && line.find('/') != std::string::npos) {
      // Still allow ashmem / dalvik-alloc style without path? skip paths with '/'
      const auto sp = line.find_last_of(' ');
      if (sp != std::string::npos && line.find('/', sp) != std::string::npos) continue;
    }
    if (b <= a || (b - a) > 32ull * 1024ull * 1024ull) continue;

    for (uintptr_t p = (a + 7) & ~uintptr_t{7}; p + br::kMapListSentinel + 8 <= b; p += 8) {
      if (!LooksLikeMapModel(p, base)) continue;
      uint8_t mode = 0;
      mem::Read(reinterpret_cast<void*>(p + br::kMapNavMode), mode);
      MarkerSnapshot m{};
      if (mode == 1 && ReadLocation(p + br::kMapNavTarget, m)) {
        best_gps = p;
        break;
      }
      if (!best && (ReadLocation(p + br::kMapNavTarget, m) || ReadLocation(p + br::kMapNavAlt, m))) {
        best = p;
      } else if (!best) {
        best = p;  // fingerprint alone — usable once pin is set
      }
    }
    if (best_gps) break;
  }
  return best_gps ? best_gps : best;
}

uintptr_t ResolveMapModel(bool force_scan) {
  uintptr_t map = detail::MapModel();
  if (map && LooksLikeMapModel(map, detail::Base())) {
    return map;
  }

  static Clock::time_point last_scan{};
  const auto now = Clock::now();
  if (!force_scan && last_scan.time_since_epoch().count() != 0 &&
      now - last_scan < std::chrono::seconds(2)) {
    return 0;
  }
  last_scan = now;

  map = ScanForMapModel();
  if (map) {
    BindMapModel(map);
    RES_LOGI("CMapModel* discovered %p", reinterpret_cast<void*>(map));
  }
  return map;
}

}  // namespace

MarkerSnapshot CaptureMarker() {
  MarkerSnapshot m;
  uintptr_t map = ResolveMapModel(false);
  if (!map) return m;
  uintptr_t loc = ActiveNavLocation(map);
  ReadLocation(loc, m);
  return m;
}

bool TeleportToMarker() {
  // Force a fresh discover attempt when user presses Go.
  ResolveMapModel(true);
  auto m = CaptureMarker();
  if (!m.valid) {
    RES_LOGW("no GPS navigation target (set map pin, then retry)");
    return false;
  }
  if (!PlausibleWorld(m.world)) {
    RES_LOGW("marker rejected (implausible coords)");
    return false;
  }

  auto local = player::Local();
  if (local.valid) {
    const float d = local.pos.DistTo(m.world);
    if (d > 15000.f) {
      RES_LOGW("teleport blocked — distance %.0f too large", d);
      return false;
    }
  }

  RES_LOGI("teleport -> marker (%.2f, %.2f, %.2f)", m.world.x, m.world.y, m.world.z);
  return player::SetPosition(m.world);
}

bool RefreshMapModel() { return ResolveMapModel(true) != 0; }

}  // namespace res::game::radar
