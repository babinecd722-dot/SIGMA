#include "hooks/plthook.h"

#include "util/log.h"
#include "util/memory.h"

#include <dlfcn.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

namespace res::plthook {
namespace {

struct Trampoline {
  void* target = nullptr;
  void* stub = nullptr;
  uint8_t saved[16]{};
  bool active = false;
};

std::mutex g_mu;
std::vector<Trampoline> g_hooks;

void* AllocPage() {
  void* p = mmap(nullptr, 4096, PROT_READ | PROT_WRITE | PROT_EXEC,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  return p == MAP_FAILED ? nullptr : p;
}

// AArch64 absolute jump: LDR X16, #8; BR X16; .quad addr
void WriteAbsJump(void* at, void* to) {
  uint32_t code[4] = {
      0x58000050u,  // LDR X16, #8
      0xD61F0200u,  // BR X16
      static_cast<uint32_t>(reinterpret_cast<uintptr_t>(to) & 0xFFFFFFFFu),
      static_cast<uint32_t>((reinterpret_cast<uintptr_t>(to) >> 32) & 0xFFFFFFFFu),
  };
  std::memcpy(at, code, sizeof(code));
  __builtin___clear_cache(reinterpret_cast<char*>(at),
                          reinterpret_cast<char*>(at) + sizeof(code));
}

}  // namespace

void* Replace(const char* /*module*/, const char* symbol, void* replacement) {
  std::lock_guard lock(g_mu);
  void* target = dlsym(RTLD_DEFAULT, symbol);
  if (!target) {
    RES_LOGW("dlsym(%s) failed", symbol);
    return nullptr;
  }

  auto* stub = AllocPage();
  if (!stub) {
    RES_LOGE("mmap trampoline failed");
    return nullptr;
  }

  Trampoline t;
  t.target = target;
  t.stub = stub;
  std::memcpy(t.saved, target, sizeof(t.saved));

  // stub: original 16 bytes + jump back to target+16
  std::memcpy(stub, t.saved, sizeof(t.saved));
  WriteAbsJump(reinterpret_cast<uint8_t*>(stub) + 16,
               reinterpret_cast<uint8_t*>(target) + 16);

  if (!mem::Protect(target, 16, PROT_READ | PROT_WRITE | PROT_EXEC)) {
    RES_LOGE("mprotect target failed");
    munmap(stub, 4096);
    return nullptr;
  }
  WriteAbsJump(target, replacement);
  t.active = true;
  g_hooks.push_back(t);
  RES_LOGI("inline hooked %s @ %p -> %p (tramp %p)", symbol, target, replacement, stub);
  return stub;
}

}  // namespace res::plthook
EOF