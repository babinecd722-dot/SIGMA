#include "ui/theme.h"

namespace res::ui {

void ApplyResolutionTheme() {
  ImGuiStyle& s = ImGui::GetStyle();
  s.WindowRounding = 10.f;
  s.ChildRounding = 8.f;
  s.FrameRounding = 6.f;
  s.PopupRounding = 8.f;
  s.ScrollbarRounding = 8.f;
  s.GrabRounding = 4.f;
  s.TabRounding = 6.f;
  s.WindowBorderSize = 1.f;
  s.FrameBorderSize = 0.f;
  s.WindowPadding = ImVec2(16, 14);
  s.FramePadding = ImVec2(10, 6);
  s.ItemSpacing = ImVec2(10, 8);
  s.ScrollbarSize = 10.f;

  ImVec4* c = s.Colors;
  c[ImGuiCol_WindowBg] = kBg;
  c[ImGuiCol_ChildBg] = kPanel;
  c[ImGuiCol_PopupBg] = kPanel;
  c[ImGuiCol_Border] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.25f);
  c[ImGuiCol_FrameBg] = ImVec4(0.12f, 0.14f, 0.18f, 1.f);
  c[ImGuiCol_FrameBgHovered] = ImVec4(0.16f, 0.19f, 0.24f, 1.f);
  c[ImGuiCol_FrameBgActive] = ImVec4(0.18f, 0.22f, 0.28f, 1.f);
  c[ImGuiCol_TitleBg] = ImVec4(0.07f, 0.08f, 0.10f, 1.f);
  c[ImGuiCol_TitleBgActive] = ImVec4(0.07f, 0.08f, 0.10f, 1.f);
  c[ImGuiCol_CheckMark] = kAccent;
  c[ImGuiCol_SliderGrab] = kAccent;
  c[ImGuiCol_SliderGrabActive] = ImVec4(0.3f, 0.95f, 0.7f, 1.f);
  c[ImGuiCol_Button] = ImVec4(0.12f, 0.16f, 0.18f, 1.f);
  c[ImGuiCol_ButtonHovered] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.35f);
  c[ImGuiCol_ButtonActive] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.55f);
  c[ImGuiCol_Header] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.20f);
  c[ImGuiCol_HeaderHovered] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.35f);
  c[ImGuiCol_HeaderActive] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.45f);
  c[ImGuiCol_Separator] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.20f);
  c[ImGuiCol_Text] = kText;
  c[ImGuiCol_TextDisabled] = kMuted;
  c[ImGuiCol_Tab] = ImVec4(0.10f, 0.12f, 0.15f, 1.f);
  c[ImGuiCol_TabHovered] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.40f);
  c[ImGuiCol_TabSelected] = ImVec4(kAccent.x, kAccent.y, kAccent.z, 0.28f);
}

}  // namespace res::ui
