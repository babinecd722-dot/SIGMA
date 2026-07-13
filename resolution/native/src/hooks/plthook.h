#pragma once

#include <cstdint>

namespace res::plthook {

// Replace GOT entry for symbol in module with replacement; returns previous.
void* Replace(const char* module, const char* symbol, void* replacement);

}  // namespace res::plthook
EOF