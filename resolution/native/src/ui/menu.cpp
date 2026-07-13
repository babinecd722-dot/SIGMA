#include "ui/menu.h"

#include "features/config.h"
#include "features/features.h"
#include "game/br_offsets.h"
#include "game/game.h"
#include "ui/theme.h"

#include "imgui.h"

#include <cstdio>

namespace res::ui {
namespace {

void SectionLabel(const char* text) {
  ImGui::PushStyleColor(ImGuiCol_Text, kAccent);
  ImGui::TextUnformatted(text);
  ImGui::PopStyleColor();
  ImGui::Separator();
}

}  // namespace

void DrawMenu() {
  auto& root = cfg::Get();
  if (!root.menu.open) return;

  ImGui::SetNextWindowSize(ImVec2(520, 420), ImGuiCond_FirstUseEver);
  ImGui::SetNextWindowPos(ImVec2(80, 60), ImGuiCond_FirstUseEver);

  ImGui::Begin("RESOLUTION", &root.menu.open,
               ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoScrollbar);

  ImGui::PushStyleColor(ImGuiCol_Text, kAccent);
  ImGui::TextUnformatted("RESOLUTION");
  ImGui::PopStyleColor();
  ImGui::SameLine();
  ImGui::TextDisabled("  ·  Black Russia  %s", br::kVersion);
  ImGui::Spacing();

  if (ImGui::BeginTabBar("##res_tabs", ImGuiTabBarFlags_None)) {
    if (ImGui::BeginTabItem("ESP")) {
      auto& e = root.esp;
      SectionLabel("Visuals");
      ImGui::Checkbox("Enable ESP", &e.enabled);
      ImGui::Checkbox("Box", &e.box);
      ImGui::SameLine();
      ImGui::Checkbox("Skeleton", &e.skeleton);
      ImGui::Checkbox("Health", &e.health);
      ImGui::SameLine();
      ImGui::Checkbox("Armour", &e.armour);
      ImGui::Checkbox("Name", &e.name);
      ImGui::SameLine();
      ImGui::Checkbox("Distance", &e.distance);
      ImGui::Checkbox("Snapline", &e.snapline);
      ImGui::Checkbox("Hide local", &e.hide_local);
      ImGui::SliderFloat("Max distance", &e.max_dist, 50.f, 600.f, "%.0f m");
      ImGui::SliderFloat("Box thickness", &e.box_thickness, 1.f, 4.f);
      ImGui::SliderFloat("Skeleton thickness", &e.skeleton_thickness, 1.f, 4.f);
      ImGui::EndTabItem();
    }

    if (ImGui::BeginTabItem("AIM")) {
      auto& a = root.aim;
      SectionLabel("Targeting");
      ImGui::Checkbox("Enable Aim", &a.enabled);
      ImGui::Checkbox("Draw FOV", &a.visible_draw_fov);
      ImGui::Checkbox("Closest to crosshair", &a.closest_to_crosshair);
      ImGui::SliderFloat("FOV (px)", &a.fov, 20.f, 400.f, "%.0f");
      ImGui::SliderFloat("Max distance", &a.max_dist, 20.f, 400.f, "%.0f m");
      ImGui::SliderFloat("Smooth X", &a.smooth_x, 1.f, 20.f);
      ImGui::SliderFloat("Smooth Y", &a.smooth_y, 1.f, 20.f);
      const char* bones[] = {"Pelvis", "Spine", "Neck", "Head"};
      int bone = a.bone;
      if (bone < 0 || bone > 3) bone = 3;
      if (ImGui::Combo("Bone", &bone, bones, 4)) a.bone = bone;
      ImGui::TextDisabled("Lock line draws on target — cam write pending RE");
      ImGui::EndTabItem();
    }

    if (ImGui::BeginTabItem("Teleport")) {
      SectionLabel("GPS marker");
      ImGui::TextWrapped(
          "1. Open map / enter interior flow\n"
          "2. Set GPS pin (CMapModel::SetGpsNavigationTarget)\n"
          "3. Close UI\n"
          "4. Press Go to marker");
      ImGui::Spacing();
      ImGui::Checkbox("Show marker ESP", &root.teleport.show_marker_esp);

      auto m = game::Marker();
      if (m.valid) {
        ImGui::Text("Marker:  %.2f  %.2f  %.2f", m.world.x, m.world.y, m.world.z);
      } else {
        ImGui::TextDisabled("No active navigation target");
        ImGui::TextDisabled("Bind CMapModel* if pool path alone is insufficient");
      }

      if (ImGui::Button("Go to marker", ImVec2(-1, 36))) {
        teleport::GoToMarker();
      }
      ImGui::EndTabItem();
    }

    if (ImGui::BeginTabItem("Misc")) {
      SectionLabel("Runtime");
      ImGui::Text("Client: %s", br::kClientSo);
      ImGui::Text("Base: %p", reinterpret_cast<void*>(game::ClientBase()));
      ImGui::Text("Ready: %s", game::Ready() ? "yes" : "no");
      auto local = game::LocalPed();
      if (local.valid) {
        ImGui::Text("Local #%d  (%.1f, %.1f, %.1f)", local.id, local.pos.x, local.pos.y,
                    local.pos.z);
      } else {
        ImGui::TextDisabled("Local ped not resolved");
      }
      ImGui::Spacing();
      if (ImGui::Button("Re-init game layer", ImVec2(-1, 32))) game::Init();
      ImGui::Checkbox("Show floating R", &root.menu.fab_visible);
      ImGui::EndTabItem();
    }

    ImGui::EndTabBar();
  }

  ImGui::End();
}

}  // namespace res::ui
EOF