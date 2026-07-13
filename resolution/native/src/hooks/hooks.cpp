#include "hooks/hooks.h"

#include "game/game.h"
#include "hooks/plthook.h"
#include "render/renderer.h"
#include "util/log.h"

#include "imgui.h"

#include <EGL/egl.h>
#include <dlfcn.h>
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
std::atomic<bool> g_frame_ok{true};
std::mutex g_touch_mu;

EGLBoolean HookedSwapBuffers(EGLDisplay dpy, EGLSurface surface) {
  if (g_frame_ok.load()) {
    // Never let overlay faults kill the process.
    EGLint w = 0, h = 0;
    if (eglQuerySurface(dpy, surface, EGL_WIDTH, &w) &&
        eglQuerySurface(dpy, surface, EGL_HEIGHT, &h) && w > 0 && h > 0) {
      if (!game::Ready()) game::Init();
      game::SetScreenSize(w, h);
      render::BeginFrame(w, h);
      render::EndFrame();
    }
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

  // Prefer GOT of the game client (and fall back to any importer). Never inline-patch libEGL.
  void* prev = plthook::Replace("libblackrussia-client.so", "eglSwapBuffers",
                                reinterpret_cast<void*>(&HookedSwapBuffers));
  if (!prev) {
    prev = plthook::Replace("", "eglSwapBuffers", reinterpret_cast<void*>(&HookedSwapBuffers));
  }
  g_orig_swap = reinterpret_cast<EglSwapBuffersFn>(prev);
  if (!g_orig_swap) {
    // Absolute fallback: call through libEGL without hook — menu won't show, but app lives.
    void* egl = dlopen("libEGL.so", RTLD_NOW);
    g_orig_swap = egl ? reinterpret_cast<EglSwapBuffersFn>(dlsym(egl, "eglSwapBuffers")) : nullptr;
    RES_LOGW("eglSwapBuffers GOT hook failed — running without overlay");
    g_installed = false;
    return false;
  }

  void* touch = plthook::Replace(
      "libblackrussia-client.so", "Java_com_blackhub_bronline_game_core_JNILib_multiTouchEvent",
      reinterpret_cast<void*>(&HookedMultiTouch));
  g_orig_touch = reinterpret_cast<MultiTouchFn>(touch);
  if (!g_orig_touch) {
    RES_LOGW("multiTouchEvent GOT miss — use NativeBridge.onTouch if wired");
  }

  RES_LOGI("hooks installed (GOT)");
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
