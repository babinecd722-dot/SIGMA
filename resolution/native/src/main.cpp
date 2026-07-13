#include "game/game.h"
#include "hooks/hooks.h"
#include "util/log.h"

#include <jni.h>

#include <atomic>
#include <chrono>
#include <thread>

namespace {

std::atomic<bool> g_started{false};

void Bootstrap() {
  RES_LOGI("RESOLUTION bootstrap");
  // Wait until client is mapped.
  for (int i = 0; i < 200; ++i) {
    if (res::game::Init()) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  if (!res::hooks::Install()) {
    RES_LOGE("hook install failed");
  }
}

}  // namespace

__attribute__((constructor)) void resolution_ctor() {
  if (g_started.exchange(true)) return;
  std::thread(Bootstrap).detach();
}

extern "C" JNIEXPORT void JNICALL
Java_com_resolution_br_NativeBridge_onTouch(JNIEnv*, jclass, jint action, jfloat x, jfloat y,
                                            jint pointer) {
  res::hooks::OnTouch(action, x, y, pointer);
}

extern "C" JNIEXPORT void JNICALL Java_com_resolution_br_NativeBridge_init(JNIEnv*, jclass) {
  res::game::Init();
  res::hooks::Install();
}

extern "C" JNIEXPORT void JNICALL
Java_com_resolution_br_NativeBridge_bindMapModel(JNIEnv*, jclass, jlong ptr) {
  res::game::BindMapModel(static_cast<uintptr_t>(ptr));
}
