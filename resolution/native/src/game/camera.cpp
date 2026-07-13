#include "game/camera.h"

#include "game/game.h"
#include "game/player.h"

#include <cmath>

namespace res::game::camera {

CameraSnapshot Capture() {
  CameraSnapshot c;
  detail::GetScreen(c.screen_w, c.screen_h);

  Mat34 view{}, proj{};
  if (detail::ViewProj(view, proj)) {
    c.view = view;
    c.proj = proj;
    c.pos = view.Pos();
    c.forward = view.At().Normalized();
    c.valid = true;
    return c;
  }

  // Camera matrix not recovered from BR client yet.
  // Fall back: origin at local ped, forward +Y flat — only for non-W2S debug.
  auto local = player::Local();
  if (local.valid) {
    c.pos = local.pos;
    c.forward = {0.f, 1.f, 0.f};
    c.fov = 70.f;
    c.valid = true;
  }
  return c;
}

bool WorldToScreen(const Vec3& world, Vec2& out) {
  Mat34 view{}, proj{};
  if (!detail::ViewProj(view, proj)) return false;  // require hooked VP — no fake SA cam

  int sw = 0, sh = 0;
  detail::GetScreen(sw, sh);
  if (sw <= 0 || sh <= 0) return false;

  const float* m = &view.m[0][0];
  const float* p = &proj.m[0][0];
  const float x = world.x, y = world.y, z = world.z;
  const float vx = m[0] * x + m[4] * y + m[8] * z + m[12];
  const float vy = m[1] * x + m[5] * y + m[9] * z + m[13];
  const float vz = m[2] * x + m[6] * y + m[10] * z + m[14];
  const float vw = m[3] * x + m[7] * y + m[11] * z + m[15];
  const float cx = p[0] * vx + p[4] * vy + p[8] * vz + p[12] * vw;
  const float cy = p[1] * vx + p[5] * vy + p[9] * vz + p[13] * vw;
  const float cw = p[3] * vx + p[7] * vy + p[11] * vz + p[15] * vw;
  if (cw < 0.001f) return false;
  const float inv = 1.f / cw;
  out.x = (sw * 0.5f) + (sw * 0.5f) * cx * inv;
  out.y = (sh * 0.5f) - (sh * 0.5f) * cy * inv;
  return true;
}

}  // namespace res::game::camera
EOF