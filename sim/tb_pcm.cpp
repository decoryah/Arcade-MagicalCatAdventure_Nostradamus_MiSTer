// ADPCM-A sample path: change the address once per 1.5 us slot (144 clocks) and check the byte is back before the next.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include "Vtb_pcm_top.h"
#include "Vtb_pcm_top__Dpi.h"
#include "verilated.h"
#include "svdpi.h"
static int sd_word(uint32_t wa) {
    if (wa < 0x80000) return wa;
    if (wa < 0x90000) return -1;
    if (wa >= 0x550000) return -2;
    if (wa >= 0x310000 && wa < 0x4D0000) {
        uint32_t w = wa & 63;
        uint32_t p = ((w >> 5) & 1) << 5 | ((w >> 3) & 1) << 4 | ((w >> 2) & 1) << 3 | ((w >> 1) & 1) << 2 | ((w >> 4) & 1) << 1 | (w & 1);
        return ((wa & ~63u) | p) - 0x10000;
    }
    return wa - 0x10000;
}
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    FILE* f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> img(n); if (fread(img.data(), 1, n, f) != (size_t)n) return 2; fclose(f);
    int slots = argc > 2 ? atoi(argv[2]) : 20000;
    int load = argc > 3 ? atoi(argv[3]) : 1;
    Vtb_pcm_top* t = new Vtb_pcm_top;
    svSetScope(svGetScopeFromName("TOP.tb_pcm_top"));
    t->clk = 0; t->init = 1; t->load_en = 0; t->addr = 0;
    auto cyc = [&](int k) { for (int i = 0; i < k; i++) { t->clk = 1; t->eval(); t->clk = 0; t->eval(); } };
    cyc(200); t->init = 0;
    while (!t->mem_ready) cyc(1);
    for (long wa = 0; wa < n / 2; wa++) { int sw = sd_word(wa); if (sw >= 0) tb_sdram_write(sw, img[2*wa] | (img[2*wa+1] << 8)); }
    cyc(50);
    t->load_en = load;
    const uint32_t PCM = 0x9A0000;
    uint32_t seed = 12345; long bad = 0; int worst = 0;
    uint32_t addr = 0;
    for (int s = 0; s < slots; s++) {
        seed = seed * 1664525u + 1013904223u;
        addr = (seed >> 8) & 0xFFFFF;
        t->addr = addr;
        // how soon does the right byte appear?
        int ok_at = -1;
        for (int c = 0; c < 144; c++) {
            cyc(1);
            if (t->data == img[PCM + addr] && ok_at < 0) ok_at = c + 1;
        }
        bool good = (t->data == img[PCM + addr]);
        if (!good) { bad++; if (bad < 10) fprintf(stderr, "slot %d addr %05x: got %02x want %02x\n", s, addr, t->data, img[PCM + addr]); }
        if (ok_at > worst) worst = ok_at;
        // addresses whose byte equals the previous one would pass trivially: negligible
    }
    fprintf(stderr, "%d slots, %ld wrong at the end of the slot; slowest byte arrived %d clocks after the address changed (slot = 144)\n", slots, bad, worst);
    delete t;
    return bad ? 1 : 0;
}
