#include "ui/fab.h"

#include "features/config.h"
#include "ui/theme.h"

#include "imgui.h"

namespace res::ui {
namespace {
bool g_dragging = false;
bool g_capture = false;
ImVec2 g_drag_off{};
}  // namespace

bool FabWantsCapture() { return g_capture; }

void DrawFab() {
  auto& menu = cfg::Get().menu;
  if (!menu.fab_visible) return;

  g_capture = false;
  const float sz = menu.fab_size;
  ImGui::SetNextWindowPos(ImVec2(menu.fab_x, menu.fab_y), ImGuiCond_Always);
  ImGui::SetNextWindowSize(ImVec2(sz + 8.f, sz + 8.f));
  ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(4, 4));
  ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, sz);
  ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0, 0, 0, 0));
  ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(0, 0, 0, 0));

  ImGui::Begin("##resolution_fab", nullptr,
               ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoScrollbar |
                   ImGuiWindowFlags_NoScrollWithMouse | ImGuiWindowFlags_NoBringToFrontOnFocus |
                   ImGuiWindowFlags_NoFocusOnAppearing);

  ImDrawList* dl = ImGui::GetWindowDrawList();
  const ImVec2 p = ImGui::GetCursorScreenPos();
  const ImVec2 center(p.x + sz * 0.5f, p.y + sz * 0.5f);

  // Soft shadow + glass disc
  dl->AddCircleFilled(ImVec2(center.x, center.y + 2.f), sz * 0.48f, IM_COL32(0, 0, 0, 70));
  dl->AddCircleFilled(center, sz * 0.46f, IM_COL32(13, 15, 20, 170));
  dl->AddCircle(center, sz * 0.46f, IM_COL32(46, 230, 166, 210), 48, 2.2f);
  dl->AddCircle(center, sz * 0.38f, IM_COL32(46, 230, 166, 50), 48, 1.2f);

  const char* r = "R";
  const ImVec2 ts = ImGui::CalcTextSize(r);
  dl->AddText(ImVec2(center.x - ts.x * 0.5f, center.y - ts.y * 0.55f), IM_COL32(46, 230, 166, 245),
              r);

  ImGui::InvisibleButton("##fab_hit", ImVec2(sz, sz));
  if (ImGui::IsItemActive() || ImGui::IsItemHovered()) g_capture = true;

  if (ImGui::IsItemActivated()) {
    g_dragging = false;
    g_drag_off = ImVec2(ImGui::GetIO().MousePos.x - menu.fab_x, ImGui::GetIO().MousePos.y - menu.fab_y);
  }
  if (ImGui::IsItemActive() && ImGui::IsMouseDragging(ImGuiMouseButton_Left, 4.f)) {
    g_dragging = true;
    menu.fab_x = ImGui::GetIO().MousePos.x - g_drag_off.x;
    menu.fab_y = ImGui::GetIO().MousePos.y - g_drag_off.y;
  }
  if (ImGui::IsItemDeactivated() && !g_dragging) {
    menu.open = !menu.open;
  }

  ImGui::End();
  ImGui::PopStyleColor(2);
  ImGui::PopStyleVar(2);
}

}  // namespace res::ui
