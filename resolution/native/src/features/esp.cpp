#include "features/features.h"

#include "features/config.h"
#include "game/game.h"
#include "game/structures.h"

#include "imgui.h"

#include <cmath>
#include <cstdio>

namespace res::esp {
namespace {

ImU32 Pack(int abgr) {
  // stored as AARRGGBB-ish int in config; convert to ImGui IM_COL32
  const int a = (abgr >> 24) & 0xFF;
  const int b = (abgr >> 16) & 0xFF;
  const int g = (abgr >> 8) & 0xFF;
  const int r = abgr & 0xFF;
  return IM_COL32(r, g, b, a ? a : 230);
}

void DrawHealthBar(ImDrawList* dl, const ImVec2& tl, const ImVec2& br, float hp, float ar) {
  const float h = br.y - tl.y;
  const float x0 = tl.x - 5.f;
  const float hp01 = hp > 1.f ? (hp / 100.f) : hp;
  const float clamped = hp01 < 0.f ? 0.f : (hp01 > 1.f ? 1.f : hp01);
  dl->AddRectFilled(ImVec2(x0 - 2.f, tl.y), ImVec2(x0 + 2.f, br.y), IM_COL32(0, 0, 0, 160));
  dl->AddRectFilled(ImVec2(x0 - 2.f, br.y - h * clamped), ImVec2(x0 + 2.f, br.y),
                    IM_COL32(46, 230, 166, 230));
  if (ar > 0.01f) {
    const float ar01 = ar > 1.f ? (ar / 100.f) : ar;
    const float a = ar01 < 0.f ? 0.f : (ar01 > 1.f ? 1.f : ar01);
    const float x1 = br.x + 5.f;
    dl->AddRectFilled(ImVec2(x1 - 2.f, tl.y), ImVec2(x1 + 2.f, br.y), IM_COL32(0, 0, 0, 160));
    dl->AddRectFilled(ImVec2(x1 - 2.f, br.y - h * a), ImVec2(x1 + 2.f, br.y),
                      IM_COL32(90, 170, 255, 230));
  }
}

}  // namespace

void Draw() {
  const auto& cfg = cfg::Get().esp;
  if (!cfg.enabled) return;
  if (!game::Ready()) return;

  auto* dl = ImGui::GetBackgroundDrawList();
  const auto local = game::LocalPed();
  const auto players = game::Players();
  const ImVec2 center(ImGui::GetIO().DisplaySize.x * 0.5f, ImGui::GetIO().DisplaySize.y * 0.5f);

  for (const auto& p : players) {
    if (!p.valid) continue;
    if (cfg.hide_local && p.is_local) continue;
    if (cfg.vehicles_only && !p.in_vehicle) continue;
    if (local.valid) {
      const float d = local.pos.DistTo(p.pos);
      if (d > cfg.max_dist) continue;
    }

    game::Vec2 feet{}, head{};
    const game::Vec3 head_w = p.bones[static_cast<int>(game::BoneId::Head)].z != 0
                                  ? p.bones[static_cast<int>(game::BoneId::Head)]
                                  : (p.pos + game::Vec3{0, 0, 1.0f});
    if (!game::WorldToScreen(p.pos, feet)) continue;
    if (!game::WorldToScreen(head_w, head)) continue;

    const float h = std::fabs(feet.y - head.y);
    if (h < 4.f) continue;
    const float w = h * 0.45f;
    const ImVec2 tl(head.x - w * 0.5f, head.y);
    const ImVec2 br(feet.x + w * 0.5f, feet.y);
    const ImU32 col = p.is_local ? Pack(cfg.box_color) : Pack(cfg.enemy_color);

    if (cfg.box) {
      dl->AddRect(tl, br, col, 0.f, 0, cfg.box_thickness);
    }
    if (cfg.snapline) {
      dl->AddLine(ImVec2(center.x, ImGui::GetIO().DisplaySize.y), ImVec2(feet.x, feet.y),
                  IM_COL32(46, 230, 166, 120), 1.2f);
    }
    if (cfg.skeleton && p.bone_count > 0) {
      for (const auto& link : game::kBoneLinks) {
        game::Vec2 a{}, b{};
        if (!game::WorldToScreen(p.bones[link[0]], a)) continue;
        if (!game::WorldToScreen(p.bones[link[1]], b)) continue;
        dl->AddLine(ImVec2(a.x, a.y), ImVec2(b.x, b.y), Pack(cfg.skeleton_color),
                    cfg.skeleton_thickness);
      }
    }
    if (cfg.health || cfg.armour) {
      DrawHealthBar(dl, tl, br, p.health, cfg.armour ? p.armour : 0.f);
    }

    char line[96];
    line[0] = 0;
    if (cfg.name && cfg.distance && local.valid) {
      std::snprintf(line, sizeof(line), "%s  [%.0fm]", p.name, local.pos.DistTo(p.pos));
    } else if (cfg.name) {
      std::snprintf(line, sizeof(line), "%s", p.name);
    } else if (cfg.distance && local.valid) {
      std::snprintf(line, sizeof(line), "%.0fm", local.pos.DistTo(p.pos));
    }
    if (line[0]) {
      const ImVec2 ts = ImGui::CalcTextSize(line);
      dl->AddText(ImVec2((tl.x + br.x) * 0.5f - ts.x * 0.5f, tl.y - ts.y - 2.f),
                  IM_COL32(240, 245, 250, 230), line);
    }
  }
}

}  // namespace res::esp
