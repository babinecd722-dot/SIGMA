#include "features/config.h"

namespace res::cfg {
namespace {
Root g_cfg{};
}

Root& Get() { return g_cfg; }

void Reset() { g_cfg = Root{}; }

}  // namespace res::cfg
EOF