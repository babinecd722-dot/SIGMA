#include "features/features.h"

#include "features/config.h"
#include "game/game.h"
#include "game/radar.h"

#include "imgui.h"

#include <cstdio>

namespace res::teleport {

void DrawMarkerEsp() {
  if (!cfg::Get().teleport.show_marker_esp) return;
  auto m = game::Marker();
  if (!m.valid) return;

  game::Vec2 s{};
  if (!game::WorldToScreen(m.world, s)) return;
  auto* dl = ImGui::GetBackgroundDrawList();
  dl->AddCircle(ImVec2(s.x, s.y), 10.f, IM_COL32(46, 230, 166, 230), 24, 2.f);
  dl->AddLine(ImVec2(s.x, s.y - 16.f), ImVec2(s.x, s.y + 16.f), IM_COL32(46, 230, 166, 180), 1.5f);
  dl->AddLine(ImVec2(s.x - 16.f, s.y), ImVec2(s.x + 16.f, s.y), IM_COL32(46, 230, 166, 180), 1.5f);

  char buf[64];
  std::snprintf(buf, sizeof(buf), "GPS  %.0f %.0f %.0f", m.world.x, m.world.y, m.world.z);
  dl->AddText(ImVec2(s.x + 12.f, s.y - 8.f), IM_COL32(240, 245, 250, 230), buf);
}

bool GoToMarker() { return game::radar::TeleportToMarker(); }

}  // namespace res::teleport
