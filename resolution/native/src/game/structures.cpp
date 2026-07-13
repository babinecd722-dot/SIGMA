#include "game/structures.h"

#include <cmath>

namespace res::game {

float Vec3::Length() const { return std::sqrt(x * x + y * y + z * z); }

float Vec3::DistTo(const Vec3& o) const { return (*this - o).Length(); }

Vec3 Vec3::Normalized() const {
  const float len = Length();
  if (len <= 1e-6f) return {};
  return (*this) * (1.f / len);
}

}  // namespace res::game
EOF