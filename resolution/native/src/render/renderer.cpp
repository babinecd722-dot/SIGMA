#include "render/renderer.h"

#include "features/features.h"
#include "ui/fab.h"
#include "ui/menu.h"
#include "ui/theme.h"
#include "util/log.h"

#include "imgui.h"
#include "imgui_impl_opengl3.h"

namespace res::render {
namespace {
bool g_ready = false;
bool g_theme = false;
}  // namespace

bool Init() {
  if (g_ready) return true;
  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO& io = ImGui::GetIO();
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
  io.IniFilename = nullptr;

  // GLES3 / GL ES shader version
  if (!ImGui_ImplOpenGL3_Init("#version 300 es")) {
    RES_LOGE("ImGui_ImplOpenGL3_Init failed");
    return false;
  }
  ui::ApplyResolutionTheme();
  g_theme = true;
  g_ready = true;
  RES_LOGI("renderer ready");
  return true;
}

void Shutdown() {
  if (!g_ready) return;
  ImGui_ImplOpenGL3_Shutdown();
  ImGui::DestroyContext();
  g_ready = false;
}

bool Ready() { return g_ready; }

void BeginFrame(int width, int height) {
  if (!g_ready) {
    if (!Init()) return;
  }
  ImGuiIO& io = ImGui::GetIO();
  io.DisplaySize = ImVec2(static_cast<float>(width), static_cast<float>(height));
  io.DeltaTime = 1.f / 60.f;
  ImGui_ImplOpenGL3_NewFrame();
  ImGui::NewFrame();
}

void EndFrame() {
  if (!g_ready) return;

  esp::Draw();
  aim::DrawFov();
  aim::Tick();
  teleport::DrawMarkerEsp();
  ui::DrawFab();
  ui::DrawMenu();

  ImGui::Render();
  ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}

}  // namespace res::render
