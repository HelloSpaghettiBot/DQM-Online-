"""Reproducible, render-only Gambatte patch. No game assets are embedded."""
from pathlib import Path
import shutil

def patch(folder, root):
    folder, root = Path(folder), Path(root)
    header = folder / 'libgambatte/libretro/dqm_appearance.h'
    shutil.copy2(root / 'native/patches/dqm_appearance.h', header)
    source = folder / 'libgambatte/libretro/libretro.cpp'
    text = source.read_text()
    if 'retro_dqm_appearance' not in text:
        text = text.replace('#include "dqm_serial.h"', '#include "dqm_serial.h"\n#include "dqm_appearance.h"')
        text = text.replace('RETRO_API void retro_dqm_link_enable', '''RETRO_API void retro_dqm_appearance(const uint8_t *data, const uint8_t *colors, bool enabled) {
  dqm::selected = enabled;
  if (enabled) {
    std::memcpy(dqm::tiles, data, 256);
    for (unsigned i=0; i<4; ++i) dqm::palette[i] = colors[i*2] | (colors[i*2+1] << 8);
  }
}
RETRO_API void retro_dqm_link_enable''')
        text = text.replace('gb.setSerialIO(value ?', 'dqm::linked = value; gb.setSerialIO(value ?')
        text = text.replace('void retro_run()\n{', '''void retro_run()
{
   dqm::active = dqm::selected && !dqm::linked && static_cast<const uint8_t *>(gb.rambank0_ptr())[0x5db] == 1;
   const uint8_t *actor = static_cast<const uint8_t *>(gb.oamram_ptr());
   if (actor[0x140] & 4) dqm::active = false;
   for (unsigned i=0; i<16; i+=4)
      if (actor[i+2] > 15 || (actor[i+3] & 8)) dqm::active = false;
''')
        source.write_text(text)
    source = folder / 'libgambatte/src/video/ppu.cpp'
    text = source.read_text()
    if 'dqm::byte' in text: return
    text = '// DQM Online modification, 2026-11-05: cosmetic player PPU sampling.\n' + text
    text = text.replace('#include "ppu.h"', '#include "ppu.h"\n#include "../../libretro/dqm_appearance.h"')
    # Each complete VRAM expression for OBJ fetches; background fetches stay intact.
    import re
    pattern = re.compile(r'(reg[01] = )(p\.vram|vram)\[(.*?)(\];)',re.S)
    def replace(m):
        if not ('spline' in m[3] and ('reg1' in m[3] or 'p.reg1' in m[3])):return m[0]
        pos = 'p.spriteList[p.currentSprite].oampos' if 'p.currentSprite' in m[3] else 'p.spriteList[nextSprite].oampos'
        return m[1]+'dqm::byte('+m[2]+', '+m[3]+', '+pos+');'
    text, count = pattern.subn(replace,text)
    assert text.count('dqm::byte') == 6
    text = text.replace('spPalette = p.spPalette + (sattrib & 7) * 4;', '''spPalette = p.spPalette + (sattrib & 7) * 4;
               video_pixel_t customPalette[4];
               if (dqm::actor(id, p.spriteMapper.oamram()[id+2]*16 + (sattrib << 10 & 0x2000))) {
                  for (unsigned c=0;c<4;++c) customPalette[c]=dqm::color<video_pixel_t>(c);
                  spPalette = customPalette;
               }''')
    text = text.replace('pixel = p.spPalette[(attrib & 7) * 4 + spdata];', '''pixel = dqm::actor(minId, p.spriteMapper.oamram()[minId+2]*16 + (attrib << 10 & 0x2000))
                 ? dqm::color<video_pixel_t>(spdata) : p.spPalette[(attrib & 7) * 4 + spdata];''')
    source.write_text(text)
