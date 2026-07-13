#include "hooks/plthook.h"

#include "util/log.h"
#include "util/memory.h"

#include <dlfcn.h>
#include <elf.h>
#include <link.h>

#include <cstring>
#include <mutex>
#include <string>

namespace res::plthook {
namespace {

std::mutex g_mu;

bool NameMatches(const char* path, const char* needle) {
  if (!needle || !needle[0]) return true;
  if (!path || !path[0]) return false;
  return std::strstr(path, needle) != nullptr;
}

void* PatchRelaTable(uintptr_t base, const ElfW(Rela)* tab, size_t bytes, const char* strtab,
                     const ElfW(Sym)* symtab, size_t syment, const char* symbol, void* replacement) {
  if (!tab || !bytes || !strtab || !symtab) return nullptr;
  const size_t n = bytes / sizeof(ElfW(Rela));
  void* prev = nullptr;
  for (size_t i = 0; i < n; ++i) {
    const auto type = ELF64_R_TYPE(tab[i].r_info);
    if (type != R_AARCH64_JUMP_SLOT && type != R_AARCH64_GLOB_DAT) continue;
    const auto sym_idx = ELF64_R_SYM(tab[i].r_info);
    const auto* sym =
        reinterpret_cast<const ElfW(Sym)*>(reinterpret_cast<const uint8_t*>(symtab) + sym_idx * syment);
    if (!mem::IsReadable(sym, sizeof(ElfW(Sym)))) continue;
    const char* name = strtab + sym->st_name;
    if (!mem::IsReadable(name, 4)) continue;
    if (std::strcmp(name, symbol) != 0) continue;

    void** slot = reinterpret_cast<void**>(base + tab[i].r_offset);
    if (!mem::IsReadable(slot, sizeof(void*))) continue;
    void* cur = *slot;
    if (!mem::WriteBytes(slot, &replacement, sizeof(void*))) {
      RES_LOGW("GOT write failed %s slot=%p", symbol, slot);
      continue;
    }
    RES_LOGI("GOT patched %s slot=%p old=%p new=%p", symbol, slot, cur, replacement);
    if (!prev) prev = cur;
  }
  return prev;
}

}  // namespace

void* Replace(const char* module_substr, const char* symbol, void* replacement) {
  std::lock_guard lock(g_mu);

  void* real = dlsym(RTLD_DEFAULT, symbol);
  if (!real) {
    void* egl = dlopen("libEGL.so", RTLD_NOW);
    real = egl ? dlsym(egl, symbol) : nullptr;
  }
  if (!real) {
    RES_LOGW("dlsym(%s) failed", symbol);
    return nullptr;
  }

  struct Ctx {
    const char* module_substr;
    const char* symbol;
    void* replacement;
    void* real;
    void* prev;
    int patches;
  } ctx{module_substr, symbol, replacement, real, nullptr, 0};

  dl_iterate_phdr(
      [](struct dl_phdr_info* info, size_t, void* data) -> int {
        auto* c = static_cast<Ctx*>(data);
        if (!NameMatches(info->dlpi_name, c->module_substr)) return 0;

        const ElfW(Dyn)* dyn = nullptr;
        for (int i = 0; i < info->dlpi_phnum; ++i) {
          if (info->dlpi_phdr[i].p_type == PT_DYNAMIC) {
            dyn = reinterpret_cast<const ElfW(Dyn)*>(info->dlpi_addr + info->dlpi_phdr[i].p_vaddr);
            break;
          }
        }
        if (!dyn || !mem::IsReadable(dyn, sizeof(ElfW(Dyn)))) return 0;

        const char* strtab = nullptr;
        const ElfW(Sym)* symtab = nullptr;
        size_t syment = sizeof(ElfW(Sym));
        const ElfW(Rela)* rela = nullptr;
        const ElfW(Rela)* plt = nullptr;
        size_t rela_sz = 0;
        size_t plt_sz = 0;

        for (auto* d = dyn; mem::IsReadable(d, sizeof(ElfW(Dyn))) && d->d_tag != DT_NULL; ++d) {
          switch (d->d_tag) {
            case DT_STRTAB:
              strtab = reinterpret_cast<const char*>(d->d_un.d_ptr);
              break;
            case DT_SYMTAB:
              symtab = reinterpret_cast<const ElfW(Sym)*>(d->d_un.d_ptr);
              break;
            case DT_SYMENT:
              syment = d->d_un.d_val ? d->d_un.d_val : sizeof(ElfW(Sym));
              break;
            case DT_RELA:
              rela = reinterpret_cast<const ElfW(Rela)*>(d->d_un.d_ptr);
              break;
            case DT_RELASZ:
              rela_sz = d->d_un.d_val;
              break;
            case DT_JMPREL:
              plt = reinterpret_cast<const ElfW(Rela)*>(d->d_un.d_ptr);
              break;
            case DT_PLTRELSZ:
              plt_sz = d->d_un.d_val;
              break;
            default:
              break;
          }
        }

        void* p = PatchRelaTable(info->dlpi_addr, plt, plt_sz, strtab, symtab, syment, c->symbol,
                                 c->replacement);
        if (!p) {
          p = PatchRelaTable(info->dlpi_addr, rela, rela_sz, strtab, symtab, syment, c->symbol,
                             c->replacement);
        }
        if (p) {
          if (!c->prev) c->prev = p;
          c->patches++;
        }
        return 0;
      },
      &ctx);

  if (!ctx.prev) {
    // No importer GOT found — keep original callable, signal failure.
    RES_LOGW("GOT hook miss for %s (module filter=%s)", symbol,
             module_substr && module_substr[0] ? module_substr : "*");
    return nullptr;
  }
  RES_LOGI("GOT hook ok %s patches=%d orig=%p", symbol, ctx.patches, ctx.prev);
  return ctx.prev ? ctx.prev : real;
}

}  // namespace res::plthook
