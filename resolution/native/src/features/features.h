#pragma once

namespace res::esp {
void Draw();
}

namespace res::aim {
void Tick();
void DrawFov();
}

namespace res::teleport {
void DrawMarkerEsp();
bool GoToMarker();
}
