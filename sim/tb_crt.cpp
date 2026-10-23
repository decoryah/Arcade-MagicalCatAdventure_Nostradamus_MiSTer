// CRT Adjust on this core's raster (see tb_crt_top.sv), measured the way a monitor sees it.
//   tb_crt <on 0/1> <hsize -16..8> <hpos -48..40> <vshift -16..10> [frames]
// Per run, over the last whole frame: rows, pixels in a row (CE pulses inside the picture), where the picture starts after
// the hsync pulse and how wide it is in clk_vid clocks, the first row's distance from the vsync pulse in lines, the first and
// last pixel index/line seen, and a check that the pixel indexes step by one along a row (no pixel lost or doubled).
#include "Vtb_crt_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
static Vtb_crt_top *dut;
static unsigned long long cyc = 0;
static inline void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); cyc++; }
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int on = argc > 1 ? atoi(argv[1]) : 0, hs = argc > 2 ? atoi(argv[2]) : 0, hp = argc > 3 ? atoi(argv[3]) : 0, vsh = argc > 4 ? atoi(argv[4]) : 0;
    int frames = argc > 5 ? atoi(argv[5]) : 4;
    dut = new Vtb_crt_top;
    dut->on_i = on;
    dut->hsize_i = hs >= 0 ? hs : 25 + hs;
    dut->hpos_i = hp >= 0 ? hp : 89 + hp;
    dut->vshift_i = vsh >= 0 ? vsh : 27 + vsh;
    for (int i = 0; i < 40; i++) tick();
    bool p_hs = false, p_vs = false, p_de = false;
    unsigned long long hs_clk = 0, de_clk = 0, vs_clk = 0, last_vs = 0;
    int fr = 0, rows = 0, lines = 0; long first = -1;
    long smin = 1 << 30, smax = -1, wmin = 1 << 30, wmax = -1, pxmin = 1 << 30, pxmax = -1, cur = 0;
    long step_ok = 0, step_bad = 0; int prev_r = -1; int first_x = -1, last_x = -1, first_y = -1, last_y = -1, row_first_x = -1;
    long fx_min = 1 << 30, fx_max = -1, lx_min = 1 << 30, lx_max = -1;
    unsigned long long period = 0;
    auto report = [&]() {
        printf("on=%d hsize=%3d hpos=%3d vshift=%3d | period %llu | lines %d rows %d | px/row %ld..%ld | picture starts %ld..%ld clocks after hsync, %ld..%ld wide"
               " | first row %ld clocks (%.2f lines) after vsync | first px %ld..%ld last px %ld..%ld | row y %d..%d | index steps ok %ld bad %ld\n",
               on, hs, hp, vsh, period, lines, rows, pxmin, pxmax, smin, smax, wmin, wmax, first, first / 3584.0, fx_min, fx_max, lx_min, lx_max,
               first_y, last_y, step_ok, step_bad);
    };
    unsigned long long limit = (unsigned long long)(frames + 3) * 931840ull * 2;
    while (fr < frames + 1 && cyc < limit) {
        tick();
        bool hsy = dut->hs_o, vsy = dut->vs_o, de = !(dut->hb_o | dut->vb_o);
        if (hsy && !p_hs) { hs_clk = cyc; lines++; }
        if (de && !p_de) {
            long s = (long)(cyc - hs_clk); de_clk = cyc; rows++;
            if (first < 0) first = (long)(cyc - vs_clk);
            if (s < smin) smin = s; if (s > smax) smax = s;
            cur = 0; prev_r = -1; row_first_x = -1;
        }
        if (de && dut->ce_o) {
            int r = dut->R, g = dut->G;
            if (cur == 0) { if (r < fx_min) fx_min = r; if (r > fx_max) fx_max = r; row_first_x = r; if (first_y < 0) first_y = g; }
            if (prev_r >= 0) { if (((r - prev_r) & 255) == 1) step_ok++; else step_bad++; }
            prev_r = r; last_x = r; last_y = g; cur++;
        }
        if (!de && p_de) {
            long w = (long)(cyc - de_clk); if (w < wmin) wmin = w; if (w > wmax) wmax = w;
            if (cur < pxmin) pxmin = cur; if (cur > pxmax) pxmax = cur;
            if (last_x < lx_min) lx_min = last_x; if (last_x > lx_max) lx_max = last_x;
        }
        if (vsy && !p_vs) {
            if (last_vs) { fr++; period = cyc - last_vs; if (fr == frames) { report(); } }
            last_vs = cyc; vs_clk = cyc; lines = 0; rows = 0; first = -1; first_y = -1;
            smin = 1 << 30; smax = -1; wmin = 1 << 30; wmax = -1; pxmin = 1 << 30; pxmax = -1; fx_min = 1 << 30; fx_max = -1; lx_min = 1 << 30; lx_max = -1;
            step_ok = step_bad = 0;
        }
        p_hs = hsy; p_vs = vsy; p_de = de;
    }
    if (fr < frames) { printf("STALLED after %llu clocks\n", cyc); delete dut; return 1; }
    delete dut;
    return 0;
}
