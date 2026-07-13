#include "util/memory.h"

#include "util/log.h"

#include <sys/mman.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>

namespace res::mem {
namespace {

enum class MapPerm : int { None = 0, Read = 1, Write = 2 };

bool RegionPerms(const void* p, std::size_t len, int& out_perms) {
  out_perms = 0;
  if (!p || len == 0) return false;
  const auto addr = reinterpret_cast<uintptr_t>(p);
  const long page = sysconf(_SC_PAGESIZE);
  const uintptr_t start = addr & ~(page - 1);
  const uintptr_t end = (addr + len + page - 1) & ~(page - 1);

  std::ifstream maps("/proc/self/maps");
  if (!maps) return false;
  std::string line;
  while (std::getline(maps, line)) {
    uintptr_t a = 0, b = 0;
    char perms[8] = {};
    if (std::sscanf(line.c_str(), "%lx-%lx %7s", &a, &b, perms) != 3) continue;
    if (b <= start || a >= end) continue;
    if (perms[0] == 'r') out_perms |= static_cast<int>(MapPerm::Read);
    if (perms[1] == 'w') out_perms |= static_cast<int>(MapPerm::Write);
    return true;
  }
  return false;
}

}  // namespace

bool IsReadable(const void* p, std::size_t len) {
  int perms = 0;
  return RegionPerms(p, len, perms) && (perms & static_cast<int>(MapPerm::Read));
}

bool IsWritable(void* p, std::size_t len) {
  int perms = 0;
  // Soft: readable heap that we may mprotect is accepted for probe.
  return RegionPerms(p, len, perms) && (perms & static_cast<int>(MapPerm::Read));
}

bool PageAlreadyWritable(void* p, std::size_t len) {
  int perms = 0;
  return RegionPerms(p, len, perms) && (perms & static_cast<int>(MapPerm::Write));
}

bool ReadBytes(const void* addr, void* dst, std::size_t len) {
  if (!IsReadable(addr, len)) return false;
  std::memcpy(dst, addr, len);
  return true;
}

bool WriteBytes(void* addr, const void* src, std::size_t len) {
  // Prefer plain store on already-writable pages (game heap / BSS).
  // Avoid mprotect noise that client integrity checks can notice.
  if (PageAlreadyWritable(addr, len)) {
    std::memcpy(addr, src, len);
    return true;
  }
  if (!Protect(addr, len, PROT_READ | PROT_WRITE)) return false;
  std::memcpy(addr, src, len);
  return true;
}

bool WriteBytesCode(void* addr, const void* src, std::size_t len) {
  if (!Protect(addr, len, PROT_READ | PROT_WRITE | PROT_EXEC)) return false;
  std::memcpy(addr, src, len);
  __builtin___clear_cache(reinterpret_cast<char*>(addr),
                          reinterpret_cast<char*>(addr) + len);
  return true;
}

ModuleInfo FindModule(const char* needle) {
  ModuleInfo info;
  std::ifstream maps("/proc/self/maps");
  std::string line;
  while (std::getline(maps, line)) {
    if (line.find(needle) == std::string::npos) continue;
    uintptr_t a = 0, b = 0;
    char perms[8] = {};
    char path[512] = {};
    if (std::sscanf(line.c_str(), "%lx-%lx %7s %*s %*s %*s %511[^\n]", &a, &b, perms, path) < 3) {
      continue;
    }
    if (perms[0] != 'r' || perms[2] != 'x') continue;
    if (!info.base) {
      info.base = reinterpret_cast<void*>(a);
      info.path = path;
    }
    info.size = reinterpret_cast<uintptr_t>(b) - reinterpret_cast<uintptr_t>(info.base);
  }
  return info;
}

void* ModuleBase(const char* name) { return FindModule(name).base; }

std::size_t ModuleSize(const char* name) { return FindModule(name).size; }

std::string ModulePath(const char* name) { return FindModule(name).path; }

bool Protect(void* addr, std::size_t len, int prot) {
  const long page = sysconf(_SC_PAGESIZE);
  auto start = reinterpret_cast<uintptr_t>(addr) & ~(page - 1);
  auto end = (reinterpret_cast<uintptr_t>(addr) + len + page - 1) & ~(page - 1);
  return mprotect(reinterpret_cast<void*>(start), end - start, prot) == 0;
}

bool Patch(void* addr, const void* data, std::size_t len) {
  return WriteBytesCode(addr, data, len);
}

}  // namespace res::mem
