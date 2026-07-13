#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace res::mem {

bool IsReadable(const void* p, std::size_t len);
bool IsWritable(void* p, std::size_t len);

template <typename T>
bool Read(const void* addr, T& out) {
  if (!IsReadable(addr, sizeof(T))) return false;
  std::memcpy(&out, addr, sizeof(T));
  return true;
}

template <typename T>
bool Write(void* addr, const T& value) {
  if (!IsWritable(addr, sizeof(T))) return false;
  std::memcpy(addr, &value, sizeof(T));
  return true;
}

bool ReadBytes(const void* addr, void* dst, std::size_t len);
// Soft data write: memcpy on RW pages, mprotect only if needed (no clear_cache).
bool WriteBytes(void* addr, const void* src, std::size_t len);
// Code patch: RWX + instruction cache flush.
bool WriteBytesCode(void* addr, const void* src, std::size_t len);
bool PageAlreadyWritable(void* p, std::size_t len);

void* ModuleBase(const char* name);
std::size_t ModuleSize(const char* name);
std::string ModulePath(const char* name);

struct ModuleInfo {
  void* base = nullptr;
  std::size_t size = 0;
  std::string path;
};

ModuleInfo FindModule(const char* needle);

bool Protect(void* addr, std::size_t len, int prot);
bool Patch(void* addr, const void* data, std::size_t len);

}  // namespace res::mem
