#include <cstdio>
#include <vector>
#include <cstdint>
#include "Vtb_ovl_top.h"
#include "verilated.h"
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_ovl_top* t = new Vtb_ovl_top;
    t->clk = 0; t->clk_vid = 0;
    uint64_t tick = 0;
    std::vector<uint8_t> fb(320 * 224 * 3, 0);
    int col = 0, row = 0, frames = 0; bool pv = true, ph = true, vis = false, pvid = false;
    while (frames < 3) {
        tick++;
        if (tick % 7 == 0) t->clk = !t->clk;
        if (tick % 24 == 0) t->clk_vid = !t->clk_vid;
        t->eval();
        if (!t->clk_vid && pvid && t->ce_pix) {
            bool hb = t->hblank, vb = t->vblank;
            if (!hb && !vb) { if (col < 320 && row < 224) { uint32_t c = t->rgb; fb[(row*320+col)*3] = c >> 16; fb[(row*320+col)*3+1] = c >> 8; fb[(row*320+col)*3+2] = c; } col++; vis = true; }
            if (hb && vis) { row++; col = 0; vis = false; }
            if (vb && !pv) { frames++; if (frames == 3) { FILE* f = fopen(argc > 1 ? argv[1] : "ovl.ppm", "wb"); fprintf(f, "P6\n320 224\n255\n"); fwrite(fb.data(), 1, fb.size(), f); fclose(f); } row = 0; col = 0; }
            if (vb) { row = 0; col = 0; vis = false; }
            pv = vb; ph = hb;
        }
        pvid = t->clk_vid;
    }
    return 0;
}
