#include "features/features.h"

#include "features/config.h"
#include "game/game.h"

#include "imgui.h"

#include <cmath>
#include <limits>
#include <vector>

namespace res::aim {
namespace {

const game::PedSnapshot* SelectTarget(const game::PedSnapshot& local,
                                      const std::vector<game::PedSnapshot>& players,
                                      const cfg::Aim& cfg, float& best_score) {
  best_score = std::numeric_limits<float>::max();
  const game::PedSnapshot* best = nullptr;
  const float cx = ImGui::GetIO().DisplaySize.x * 0.5f;
  const float cy = ImGui::GetIO().DisplaySize.y * 0.5f;

  for (const auto& p : players) {
    if (!p.valid || p.is_local) continue;
    const float dist = local.pos.DistTo(p.pos);
    if (dist > cfg.max_dist) continue;

    const int bone = cfg.bone;
    game::Vec3 aim_pos = p.pos;
    if (bone >= 0 && bone < p.bone_count) aim_pos = p.bones[bone];

    game::Vec2 screen{};
    if (!game::WorldToScreen(aim_pos, screen)) continue;
    const float dx = screen.x - cx;
    const float dy = screen.y - cy;
    const float fov_d = std::sqrt(dx * dx + dy * dy);
    if (fov_d > cfg.fov) continue;

    const float score = cfg.closest_to_crosshair ? fov_d : dist;
    if (score < best_score) {
      best_score = score;
      best = &p;
    }
  }
  return best;
}

}  // namespace

void DrawFov() {
  const auto& cfg = cfg::Get().aim;
  if (!cfg.enabled || !cfg.visible_draw_fov) return;
  auto* dl = ImGui::GetBackgroundDrawList();
  const ImVec2 c(ImGui::GetIO().DisplaySize.x * 0.5f, ImGui::GetIO().DisplaySize.y * 0.5f);
  dl->AddCircle(c, cfg.fov, IM_COL32(46, 230, 166, 90), 64, 1.5f);
}

void Tick() {
  const auto& cfg = cfg::Get().aim;
  if (!cfg.enabled) return;
  if (!game::Ready()) return;

  const auto local = game::LocalPed();
  if (!local.valid) return;
  const auto players = game::Players();

  float score = 0.f;
  const auto* target = SelectTarget(local, players, cfg, score);
  if (!target) return;

  game::Vec3 aim = target->pos;
  if (cfg.bone >= 0 && cfg.bone < target->bone_count) aim = target->bones[cfg.bone];

  game::Vec2 screen{};
  if (!game::WorldToScreen(aim, screen)) return;

  // Visual lock indicator — camera write path not fully recovered yet.
  auto* dl = ImGui::GetBackgroundDrawList();
  dl->AddLine(ImVec2(ImGui::GetIO().DisplaySize.x * 0.5f, ImGui::GetIO().DisplaySize.y * 0.5f),
              ImVec2(screen.x, screen.y), IM_COL32(46, 230, 166, 200), 1.4f);
  dl->AddCircleFilled(ImVec2(screen.x, screen.y), 3.5f, IM_COL32(46, 230, 166, 230));
}

}  // namespace res::aim
EOF