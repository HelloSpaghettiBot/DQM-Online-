// DQM Online cosmetic render hook, 2026-11-05. GPL-2.0-or-later.
// Changes PPU sampling only. Never changes emulated ROM/RAM or serialized state.
#ifndef DQM_APPEARANCE_H
#define DQM_APPEARANCE_H
#include <cstdint>
#include <cstring>
namespace dqm {
inline uint8_t tiles[256] = {};
inline uint16_t palette[4] = {};
inline bool selected = false, active = false, linked = false;
inline bool actor(unsigned oampos, unsigned address) {
    return active && oampos < 16 && address < 256;
}
inline unsigned byte(const uint8_t *vram, unsigned address, unsigned oampos) {
    return actor(oampos, address) ? tiles[address] : vram[address];
}
template<class T> inline T color(unsigned index) {
    unsigned c = palette[index & 3], r = c & 31, g = (c >> 5) & 31, b = (c >> 10) & 31;
#ifdef VIDEO_RGB565
    return T((r << 11) | (((g << 1) | (g >> 4)) << 5) | b);
#elif defined(VIDEO_ABGR1555)
    return T((b << 10) | (g << 5) | r);
#else
    return T(((r * 255 / 31) << 16) | ((g * 255 / 31) << 8) | (b * 255 / 31));
#endif
}
}
#endif
