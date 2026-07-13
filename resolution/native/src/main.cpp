#include "game/game.h"
#include "hooks/hooks.h"
#include "util/log.h"

#include <jni.h>
#include <pthread.h>

#include <atomic>
#include <chrono>
#include <thread>

namespace {

std::atomic<bool> g_started{false};

void* BootstrapThread(void*) {
  RES_LOGI("RESOLUTION bootstrap");
  for (int i = 0; i < 300; ++i) {
    if (res::game::Init()) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  if (!res::game::Ready()) {
    RES_LOGW("client not ready yet");
  }
  // Let importer PLT resolve before GOT patch.
  std::this_thread::sleep_for(std::chrono::milliseconds(800));
  if (!res::hooks::Install()) {
    RES_LOGW("overlay hook not installed — game continues");
  }
  return nullptr;
}

void StartOnce() {
  if (g_started.exchange(true)) return;
  pthread_t th;
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  if (pthread_create(&th, &attr, &BootstrapThread, nullptr) != 0) {
    RES_LOGE("pthread_create failed");
    g_started = false;
  }
  pthread_attr_destroy(&attr);
}

}  // namespace

// Do not use __attribute__((constructor)) — it runs during reloc and has
// crashed launchers when combined with early EGL hooks.

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* /*vm*/, void* /*reserved*/) {
  RES_LOGI("JNI_OnLoad");
  StartOnce();
  return JNI_VERSION_1_6;
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
