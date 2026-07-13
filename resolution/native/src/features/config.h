#pragma once

#include "game/structures.h"

namespace res::cfg {

struct Esp {
  bool enabled = true;
  bool box = true;
  bool skeleton = true;
  bool health = true;
  bool armour = true;
  bool name = true;
  bool distance = true;
  bool snapline = false;
  bool vehicles_only = false;
  float max_dist = 300.f;
  float box_thickness = 1.6f;
  float skeleton_thickness = 1.4f;
  int box_color = 0xE62EE6A6;      // ABGR-ish via ImU32 packing later
  int skeleton_color = 0xE6FFFFFF;
  int enemy_color = 0xE6FF5C5C;
  bool hide_local = true;
};

struct Aim {
  bool enabled = false;
  bool visible_draw_fov = true;
  bool smooth = true;
  bool target_npc_skip = true;  // players only (pool)
  float fov = 120.f;
  float smooth_x = 6.f;
  float smooth_y = 6.f;
  float max_dist = 200.f;
  int bone = 3;  // BoneId::Head
  bool closest_to_crosshair = true;
  bool ignore_team = true;  // reserved — team not recovered
};

struct Teleport {
  bool show_marker_esp = true;
  // Flow: set GPS pin in BR map UI → close → press Go
};

struct Menu {
  bool open = false;
  bool fab_visible = true;
  float fab_x = 48.f;
  float fab_y = 180.f;
  float fab_size = 56.f;
};

struct Root {
  Esp esp{};
  Aim aim{};
  Teleport teleport{};
  Menu menu{};
};

Root& Get();
void Reset();

}  // namespace res::cfg
EOF