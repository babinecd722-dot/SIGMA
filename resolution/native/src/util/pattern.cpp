#include "util/pattern.h"

#include "util/memory.h"

#include <cctype>
#include <cstdlib>
#include <sstream>

namespace res::pattern {

BytePattern Parse(const char* ida_style, const char* name) {
  BytePattern out;
  out.name = name ? name : "";
  std::istringstream ss(ida_style);
  std::string tok;
  while (ss >> tok) {
    if (tok == "?" || tok == "??") {
      out.bytes.push_back(-1);
      continue;
    }
    out.bytes.push_back(static_cast<int>(std::strtoul(tok.c_str(), nullptr, 16)));
  }
  return out;
}

std::optional<uintptr_t> Find(uintptr_t base, std::size_t size, const BytePattern& pat) {
  if (!base || !size || pat.bytes.empty()) return std::nullopt;
  const auto* data = reinterpret_cast<const uint8_t*>(base);
  const std::size_t n = pat.bytes.size();
  if (n > size) return std::nullopt;
  for (std::size_t i = 0; i + n <= size; ++i) {
    bool ok = true;
    for (std::size_t j = 0; j < n; ++j) {
      if (pat.bytes[j] < 0) continue;
      if (data[i + j] != static_cast<uint8_t>(pat.bytes[j])) {
        ok = false;
        break;
      }
    }
    if (ok) return base + i;
  }
  return std::nullopt;
}

std::optional<uintptr_t> Find(const char* module, const BytePattern& pat) {
  auto info = mem::FindModule(module);
  if (!info.base || !info.size) return std::nullopt;
  return Find(reinterpret_cast<uintptr_t>(info.base), info.size, pat);
}

uintptr_t ResolveAdrpAdd(uintptr_t adrp_instr) {
  // ADRP Xd, imm; ADD Xd, Xd, imm12
  const uint32_t adrp = *reinterpret_cast<const uint32_t*>(adrp_instr);
  const uint32_t add = *reinterpret_cast<const uint32_t*>(adrp_instr + 4);
  if ((adrp & 0x9F000000u) != 0x90000000u) return 0;
  if ((add & 0xFFC00000u) != 0x91000000u) return 0;
  const int64_t immlo = (adrp >> 29) & 0x3;
  int64_t immhi = (adrp >> 5) & 0x7FFFF;
  if (immhi & 0x40000) immhi |= ~0x7FFFFLL;
  const int64_t page = ((immhi << 2) | immlo) << 12;
  const uintptr_t pc_page = adrp_instr & ~0xFFFull;
  const uint32_t imm12 = (add >> 10) & 0xFFF;
  const uint32_t shift = (add >> 22) & 0x1;
  return pc_page + page + (imm12 << (shift ? 12 : 0));
}

uintptr_t ResolveAdrpLdr(uintptr_t adrp_instr) {
  const uint32_t adrp = *reinterpret_cast<const uint32_t*>(adrp_instr);
  const uint32_t ldr = *reinterpret_cast<const uint32_t*>(adrp_instr + 4);
  if ((adrp & 0x9F000000u) != 0x90000000u) return 0;
  if ((ldr & 0xFFC00000u) != 0xF9400000u) return 0;
  const int64_t immlo = (adrp >> 29) & 0x3;
  int64_t immhi = (adrp >> 5) & 0x7FFFF;
  if (immhi & 0x40000) immhi |= ~0x7FFFFLL;
  const int64_t page = ((immhi << 2) | immlo) << 12;
  const uintptr_t pc_page = adrp_instr & ~0xFFFull;
  const uint32_t imm12 = (ldr >> 10) & 0xFFF;
  const uintptr_t slot = pc_page + page + (imm12 << 3);
  uintptr_t value = 0;
  if (!mem::Read(reinterpret_cast<void*>(slot), value)) return 0;
  return value;
}

}  // namespace res::pattern
