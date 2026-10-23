// What the framework's scandoubler makes of this core's raster (see tb_sd_top.sv).
//   tb_sd <frames> <fx 0..7> <forced_scandoubler 0/1> <bad_blank 0/1>
// Prints, per frame between two vertical syncs: the period, the horizontal syncs and picture lines seen and the picture's
// width; and whether each source line came out in order (the picture's green is the line number), twice when doubled.
#include "Vtb_sd_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
static Vtb_sd_top *dut;
static unsigned long long cycles = 0;
static inline void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); cycles++; }
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int frames = argc > 1 ? atoi(argv[1]) : 6, fx = argc > 2 ? atoi(argv[2]) : 0, fsd = argc > 3 ? atoi(argv[3]) : 0;
    int bad = argc > 4 ? atoi(argv[4]) : 0;
    dut = new Vtb_sd_top;
    dut->fx = fx; dut->fsd = fsd; dut->bad_blank = bad;
    for (int i = 0; i < 40; i++) tick();
    bool phs = false, pvs = false, pde = false;
    unsigned long long last_hs = 0, last_vs = 0, hs_sum = 0, hs_n = 0;
    long lines_de = 0, hs_edges = 0, de_pix_line = 0; long px_min = 1 << 30, px_max = -1;
    long de_clks = 0, dc_min = 1 << 30, dc_max = -1;                       // clocks with DE high per line (a count independent of CE_PIXEL's phase)
    unsigned long long tot_hs = 0, tot_vs = 0, tot_de = 0;
    std::vector<int> first_g;
    int fr = 0; unsigned long long limit = (unsigned long long)(frames + 4) * 940000ull;     // a frame is 448 x 260 x 8 = 931,840 clocks
    printf("frame |   period | HS edges | DE lines | px/line | DE clks | HS period (clk) | line check\n");
    while (fr < frames + 2 && cycles < limit) {
        tick();
        bool hs = dut->VGA_HS, vs = dut->VGA_VS, de = dut->VGA_DE;
        if (dut->CE_PIXEL && de) { if (de_pix_line == 0) first_g.push_back(dut->VGA_G); de_pix_line++; }
        if (hs && !phs) tot_hs++;
        if (de && !pde) tot_de++;
        if (vs && !pvs) tot_vs++;
        if (hs && !phs) { hs_edges++; if (last_hs) { hs_sum += cycles - last_hs; hs_n++; } last_hs = cycles; }
        if (de) de_clks++;
        if (de && !pde) { lines_de++; de_pix_line = 0; de_clks = 1; }
        if (!de && pde) {
            if (de_pix_line < px_min) px_min = de_pix_line; if (de_pix_line > px_max) px_max = de_pix_line;
            if (de_clks < dc_min) dc_min = de_clks; if (de_clks > dc_max) dc_max = de_clks;
        }
        if (vs && !pvs) {
            if (last_vs) {
                fr++;
                if (fr >= 2) {
                    char chk[160] = "";
                    size_t n = first_g.size();
                    if (n) {
                        long same = 0, step = 0, pairs = 0;
                        int rep = (int)n >= 400 ? 2 : 1;
                        for (size_t i = 0; i + rep < n; i += rep) {
                            pairs++;
                            bool eq = true; for (int k = 1; k < rep; k++) if (first_g[i + k] != first_g[i]) eq = false;
                            if (eq) same++;
                            if (i + 2 * rep <= n - 1 && ((first_g[i + rep] - first_g[i]) & 255) == 1) step++;
                        }
                        snprintf(chk, sizeof chk, "%zu lines x%d, %ld/%ld repeats identical, %ld/%ld steps +1", n, rep, same, pairs, step, pairs);
                    }
                    printf("%5d | %8llu | %8ld | %8ld | %3ld-%-3ld | %4ld-%-4ld | %15.1f | %s\n", fr, cycles - last_vs, hs_edges, lines_de, px_min, px_max,
                           dc_min, dc_max, hs_n ? (double)hs_sum / hs_n : 0.0, chk);
                }
            }
            first_g.clear();
            last_vs = cycles; hs_edges = 0; lines_de = 0; px_min = 1 << 30; px_max = -1; hs_sum = 0; hs_n = 0; dc_min = 1 << 30; dc_max = -1;
        }
        phs = hs; pvs = vs; pde = de;
    }
    printf("totals over %llu clocks: VGA_VS rises %llu, VGA_HS rises %llu, DE rises %llu\n", cycles, tot_vs, tot_hs, tot_de);
    printf("%s after %llu clocks (%d frames counted)\n", fr >= frames + 2 ? "done" : "STALLED: no vertical sync", cycles, fr);
    delete dut;
    return fr >= frames + 2 ? 0 : 1;
}
