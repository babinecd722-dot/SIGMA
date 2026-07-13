#include "game/game.h"

#include "game/br_offsets.h"
#include "game/camera.h"
#include "game/player.h"
#include "game/radar.h"
#include "util/log.h"
#include "util/memory.h"

#include <cstring>
#include <mutex>

namespace res::game {
namespace {

std::mutex g_mu;
uintptr_t g_base = 0;
std::size_t g_size = 0;
bool g_ready = false;
int g_sw = 0;
int g_sh = 0;
Mat34 g_view{};
Mat34 g_proj{};
bool g_has_vp = false;
uintptr_t g_map_model = 0;  // optional, set when Gui path resolved

}  // namespace

namespace detail {

uintptr_t Base() { return g_base; }
std::size_t Size() { return g_size; }
uintptr_t MapModel() { return g_map_model; }

void GetScreen(int& w, int& h) {
  w = g_sw;
  h = g_sh;
}

bool ViewProj(Mat34& view, Mat34& proj) {
  if (!g_has_vp) return false;
  view = g_view;
  proj = g_proj;
  return true;
}

uintptr_t Deref(uintptr_t addr) {
  uintptr_t v = 0;
  if (!addr) return 0;
  mem::Read(reinterpret_cast<void*>(addr), v);
  return v;
}

bool ReadMat(uintptr_t addr, Mat34& out) {
  return mem::ReadBytes(reinterpret_cast<void*>(addr), &out, sizeof(out));
}

uintptr_t PlayerPool() {
  if (!g_base) return 0;
  return Deref(g_base + br::kPlayerPoolSlot);
}

}  // namespace detail

bool Init() {
  std::lock_guard lock(g_mu);
  auto mod = mem::FindModule(br::kClientSo);
  if (!mod.base) {
    RES_LOGW("%s not mapped", br::kClientSo);
    return false;
  }
  g_base = reinterpret_cast<uintptr_t>(mod.base);
  g_size = mod.size;
  g_ready = true;
  RES_LOGI("BR %s base=%p size=0x%zx pool_slot=0x%lx", br::kVersion, mod.base, mod.size,
           static_cast<unsigned long>(br::kPlayerPoolSlot));
  return true;
}

void Shutdown() {
  std::lock_guard lock(g_mu);
  g_ready = false;
  g_base = 0;
  g_size = 0;
  g_map_model = 0;
}

bool Ready() {
  std::lock_guard lock(g_mu);
  return g_ready && g_base != 0;
}

uintptr_t ClientBase() { return g_base; }
std::size_t ClientSize() { return g_size; }

void SetScreenSize(int w, int h) {
  std::lock_guard lock(g_mu);
  g_sw = w;
  g_sh = h;
}

void SetViewProjection(const float* view16, const float* proj16) {
  std::lock_guard lock(g_mu);
  if (view16) std::memcpy(g_view.m, view16, sizeof(float) * 16);
  if (proj16) std::memcpy(g_proj.m, proj16, sizeof(float) * 16);
  g_has_vp = view16 && proj16;
}

void BindNetGame(uintptr_t) {
  // retained for API compat — BR uses PlayerPool slot, not SA-MP NetGame
}

void BindMapModel(uintptr_t map_model) {
  std::lock_guard lock(g_mu);
  g_map_model = map_model;
  RES_LOGI("CMapModel* bound %p", reinterpret_cast<void*>(map_model));
}

CameraSnapshot Camera() { return camera::Capture(); }
MarkerSnapshot Marker() { return radar::CaptureMarker(); }
PedSnapshot LocalPed() { return player::Local(); }
std::vector<PedSnapshot> Players() { return player::All(); }
bool WorldToScreen(const Vec3& world, Vec2& out) { return camera::WorldToScreen(world, out); }
bool SetLocalPosition(const Vec3& pos) { return player::SetPosition(pos); }
bool GetBone(uintptr_t ped, BoneId bone, Vec3& out) { return player::GetBone(ped, bone, out); }

}  // namespace res::game
EOF