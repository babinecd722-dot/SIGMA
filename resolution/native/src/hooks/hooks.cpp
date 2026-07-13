#include "hooks/hooks.h"

#include "game/game.h"
#include "hooks/plthook.h"
#include "render/renderer.h"
#include "util/log.h"

#include "imgui.h"

#include <EGL/egl.h>
#include <jni.h>

#include <atomic>
#include <mutex>

namespace res::hooks {
namespace {

using EglSwapBuffersFn = EGLBoolean (*)(EGLDisplay, EGLSurface);
using MultiTouchFn = void (*)(JNIEnv*, jclass, jint, jint, jint, jint, jint, jint, jint, jint);

EglSwapBuffersFn g_orig_swap = nullptr;
MultiTouchFn g_orig_touch = nullptr;
std::atomic<bool> g_installed{false};
std::mutex g_touch_mu;

EGLBoolean HookedSwapBuffers(EGLDisplay dpy, EGLSurface surface) {
  EGLint w = 0, h = 0;
  eglQuerySurface(dpy, surface, EGL_WIDTH, &w);
  eglQuerySurface(dpy, surface, EGL_HEIGHT, &h);
  if (w > 0 && h > 0) {
    if (!game::Ready()) game::Init();
    game::SetScreenSize(w, h);
    render::BeginFrame(w, h);
    render::EndFrame();
  }
  return g_orig_swap ? g_orig_swap(dpy, surface) : EGL_FALSE;
}

void HookedMultiTouch(JNIEnv* env, jclass clazz, jint action, jint pointer_action, jint x0,
                      jint y0, jint x1, jint y1, jint x2, jint y2) {
  OnTouch(action, static_cast<float>(x0), static_cast<float>(y0), 0);
  if (g_orig_touch) {
    g_orig_touch(env, clazz, action, pointer_action, x0, y0, x1, y1, x2, y2);
  }
}

}  // namespace

bool Install() {
  if (g_installed.exchange(true)) return true;

  void* prev = plthook::Replace("libEGL.so", "eglSwapBuffers",
                                reinterpret_cast<void*>(&HookedSwapBuffers));
  g_orig_swap = reinterpret_cast<EglSwapBuffersFn>(prev);
  if (!g_orig_swap) {
    RES_LOGE("failed to hook eglSwapBuffers");
    g_installed = false;
    return false;
  }

  void* touch = plthook::Replace(
      "libblackrussia-client.so", "Java_com_blackhub_bronline_game_core_JNILib_multiTouchEvent",
      reinterpret_cast<void*>(&HookedMultiTouch));
  g_orig_touch = reinterpret_cast<MultiTouchFn>(touch);
  if (!g_orig_touch) {
    RES_LOGW("multiTouchEvent hook missing — FAB needs NativeBridge.onTouch fallback");
  }

  RES_LOGI("hooks installed");
  return true;
}

void Remove() { g_installed = false; }

void OnTouch(int action, float x, float y, int /*pointer_id*/) {
  std::lock_guard lock(g_touch_mu);
  if (!ImGui::GetCurrentContext()) return;
  ImGuiIO& io = ImGui::GetIO();
  io.AddMousePosEvent(x, y);
  if (action == 0) io.AddMouseButtonEvent(0, true);
  if (action == 1) io.AddMouseButtonEvent(0, false);
}

}  // namespace res::hooks
