#pragma once

namespace res::plthook {

// Patch ELF JUMP_SLOT / GLOB_DAT relocations that resolve to `symbol`.
// Leaves the real function body untouched. Returns previous pointer, or nullptr.
void* Replace(const char* module_substr, const char* symbol, void* replacement);

}  // namespace res::plthook
