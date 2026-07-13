#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace res::pattern {

struct BytePattern {
  std::vector<int> bytes;  // -1 = wildcard
  std::string name;
};

BytePattern Parse(const char* ida_style, const char* name = "");

std::optional<uintptr_t> Find(uintptr_t base, std::size_t size, const BytePattern& pat);
std::optional<uintptr_t> Find(const char* module, const BytePattern& pat);

// ARM64: resolve ADRP+ADD / LDR literal helpers
uintptr_t ResolveAdrpAdd(uintptr_t adrp_instr);
uintptr_t ResolveAdrpLdr(uintptr_t adrp_instr);

}  // namespace res::pattern
EOF