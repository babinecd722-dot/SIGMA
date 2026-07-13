#include "util/memory.h"

#include "util/log.h"

#include <fcntl.h>
#include <link.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstdio>
#include <fstream>
#include <sstream>

namespace res::mem {
namespace {

bool Probe(const void* p, std::size_t len, int prot_need) {
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
    const bool r = perms[0] == 'r';
    const bool w = perms[1] == 'w';
    if ((prot_need & PROT_READ) && !r) return false;
    if ((prot_need & PROT_WRITE) && !w) {
      // writable check is soft — we may mprotect later
    }
    return true;
  }
  return false;
}

}  // namespace

bool IsReadable(const void* p, std::size_t len) {
  return Probe(p, len, PROT_READ);
}

bool IsWritable(void* p, std::size_t len) {
  return Probe(p, len, PROT_READ);
}

bool ReadBytes(const void* addr, void* dst, std::size_t len) {
  if (!IsReadable(addr, len)) return false;
  std::memcpy(dst, addr, len);
  return true;
}

bool WriteBytes(void* addr, const void* src, std::size_t len) {
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
  return WriteBytes(addr, data, len);
}

}  // namespace res::mem
EOF