#pragma once

#include <cstdint>

namespace res::game {

#pragma pack(push, 1)

struct Vec2 {
  float x = 0.f;
  float y = 0.f;
};

struct Vec3 {
  float x = 0.f;
  float y = 0.f;
  float z = 0.f;

  float Length() const;
  float DistTo(const Vec3& o) const;
  Vec3 Normalized() const;
  Vec3 operator+(const Vec3& o) const { return {x + o.x, y + o.y, z + o.z}; }
  Vec3 operator-(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
  Vec3 operator*(float s) const { return {x * s, y * s, z * s}; }
};

struct Mat34 {
  float m[4][4];

  Vec3 Right() const { return {m[0][0], m[1][0], m[2][0]}; }
  Vec3 Up() const { return {m[0][1], m[1][1], m[2][1]}; }
  Vec3 At() const { return {m[0][2], m[1][2], m[2][2]}; }
  Vec3 Pos() const { return {m[0][3], m[1][3], m[2][3]}; }
  void SetPos(const Vec3& p) {
    m[0][3] = p.x;
    m[1][3] = p.y;
    m[2][3] = p.z;
  }
};

// Placeable / entity layout calibrated for BR 16.89.x (SA Android lineage).
// Offsets are version-gated in offsets.h and applied via accessors.
struct PedSnapshot {
  bool valid = false;
  int id = -1;
  uintptr_t ptr = 0;
  Vec3 pos{};
  Vec3 velocity{};
  float health = 0.f;
  float armour = 0.f;
  int bone_count = 0;
  Vec3 bones[24]{};
  bool is_local = false;
  bool is_visible = true;
  bool in_vehicle = false;
  char name[32]{};
};

struct CameraSnapshot {
  bool valid = false;
  Mat34 view{};
  Mat34 proj{};
  Vec3 pos{};
  Vec3 forward{};
  float fov = 70.f;
  int screen_w = 0;
  int screen_h = 0;
};

struct MarkerSnapshot {
  bool valid = false;
  Vec3 world{};
  bool is_gps = false;
};

#pragma pack(pop)

enum class BoneId : int {
  Pelvis = 0,
  Spine = 1,
  Neck = 2,
  Head = 3,
  LClavicle = 4,
  LUpperArm = 5,
  LForeArm = 6,
  LHand = 7,
  RClavicle = 8,
  RUpperArm = 9,
  RForeArm = 10,
  RHand = 11,
  LThigh = 12,
  LCalf = 13,
  LFoot = 14,
  RThigh = 15,
  RCalf = 16,
  RFoot = 17,
  Count = 18
};

inline constexpr int kBoneLinks[][2] = {
    {1, 2},  {2, 3},  {2, 4},  {4, 5},   {5, 6},   {6, 7},  {2, 8},
    {8, 9},  {9, 10}, {10, 11}, {1, 12}, {12, 13}, {13, 14}, {1, 15},
    {15, 16}, {16, 17},
};

}  // namespace res::game
