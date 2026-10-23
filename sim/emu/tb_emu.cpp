// End-to-end bench of the MiSTer top (MCatAdv.sv): plays the HPS. It
//   * drives the four clocks from one base tick (1/1344 us): clk_sys 96 MHz, clk_snd 48 MHz, clk_vid 56 MHz,
//   * loads the ROM image (MRA index 0), either streamed through the ioctl port or, with FAST=1, the way Main_MiSTer does
//     it for the MRA's address= attribute: the whole image copied into the DDR3 at byte 0x32000000, then a download that
//     carries no bytes, only a start address (the image's length),
//   * checks the loader's work against the layout of target/mister/mcatadv_mem.sv (every word of the image where the
//     memory's ports read it) and the configuration the loader captured,
//   * sets the OSD options and runs frames, measuring the picture as the monitor and the scaler get it.
//
//   tb_emu <image.rom> <frames after the load> <out-prefix>      (environment variables: see sim/emu/run_emu.sh)
#include "Vtb_emu_top.h"
#include "Vtb_emu_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static Vtb_emu_top *dut;
static unsigned long long tick_n = 0, vclk = 0, sclk = 0;     // base ticks, clk_vid cycles, clk_sys cycles
#define HPSV(n) dut->rootp->tb_emu_top__DOT__u_emu__DOT__hps_io__DOT__##n
#define EMUV(n) dut->rootp->tb_emu_top__DOT__u_emu__DOT__##n
static unsigned errors = 0;
static int env_int(const char *n, int d) { const char *v = getenv(n); return v ? atoi(v) : d; }

// ---------------------------------------------------------------- the picture as the scaler gets it (VGA_*), per frame
static std::vector<unsigned> px_now, px_last;
static int rows_now = 0, width_now = 0, rows_last = 0, width_last = 0, cur_w = 0;
static int frames_done = 0;
static unsigned long long last_vs_clk = 0, frame_period = 0;
static unsigned long long n_vs = 0, n_hs = 0, n_de = 0;
// geometry in clk_vid clocks: where each row starts after the hsync pulse and how long it is, the first row's distance from vsync
static bool p_hs = false, p_vs = false, p_de = false;
static unsigned long long g_hs_clk = 0, g_de_clk = 0, g_vs_clk = 0; static long g_first = -1;
static long g_smin = 1 << 30, g_smax = -1, g_wmin = 1 << 30, g_wmax = -1;
static int g_rows = 0, g_lines = 0;
static int geo_rows = 0, geo_lines = 0; static long geo_first = -1, geo_smin = 0, geo_smax = 0, geo_wmin = 0, geo_wmax = 0;
static unsigned long long ddr_rot_at_fast_start = 0;

static void video_watch() {                 // at every clk_vid falling edge
    bool hs = dut->VGA_HS, vs = dut->VGA_VS, de = dut->VGA_DE;
    if (hs && !p_hs) { n_hs++; g_lines++; g_hs_clk = vclk; }
    if (de && !p_de) {
        n_de++; g_rows++; g_de_clk = vclk;
        long s = (long)(vclk - g_hs_clk);
        if (g_first < 0) g_first = (long)(vclk - g_vs_clk);
        if (s < g_smin) g_smin = s; if (s > g_smax) g_smax = s;
        if (cur_w > width_now) width_now = cur_w;
        cur_w = 0; rows_now++;
    }
    if (!de && p_de) { long w = (long)(vclk - g_de_clk); if (w < g_wmin) g_wmin = w; if (w > g_wmax) g_wmax = w; }
    if (vs && !p_vs) {                      // a frame ends
        n_vs++;
        if (cur_w > width_now) width_now = cur_w;
        px_last.swap(px_now); rows_last = rows_now; width_last = width_now;
        px_now.clear(); rows_now = 0; width_now = 0; cur_w = 0;
        frame_period = vclk - last_vs_clk; last_vs_clk = vclk; frames_done++;
        geo_first = g_first; geo_rows = g_rows; geo_lines = g_lines; geo_smin = g_smin; geo_smax = g_smax; geo_wmin = g_wmin; geo_wmax = g_wmax;
        g_vs_clk = vclk; g_lines = 0; g_first = -1; g_rows = 0; g_smin = 1 << 30; g_smax = -1; g_wmin = 1 << 30; g_wmax = -1;
    }
    if (dut->CE_PIXEL && de) {
        px_now.push_back(((unsigned)dut->VGA_R << 16) | ((unsigned)dut->VGA_G << 8) | dut->VGA_B);
        cur_w++;
    }
    p_hs = hs; p_vs = vs; p_de = de;
}

static inline void step() {
    tick_n++;
    bool ch = false, sris = false, vfall = false;
    if (tick_n % 7 == 0)  { dut->clk_sys_i = !dut->clk_sys_i; ch = true; if (dut->clk_sys_i) sris = true; }
    if (tick_n % 14 == 7) { dut->clk_snd_i = !dut->clk_snd_i; ch = true; }              // 48 MHz, rising with every second clk_sys rise
    if (tick_n % 12 == 0) { dut->clk_vid_i = !dut->clk_vid_i; ch = true; if (!dut->clk_vid_i) vfall = true; }
    if (tick_n % 26 == 0) { dut->CLK_50M = !dut->CLK_50M; ch = true; }
    if (ch) dut->eval();
    if (sris) sclk++;
    if (vfall) { vclk++; video_watch(); }
}
static void run_sys(long n) { unsigned long long t = sclk + n; while (sclk < t) step(); }
static void run_vid(long n) { unsigned long long t = vclk + n; while (vclk < t) step(); }

static void set_status(int bit, int v) {
    int w = bit / 32, b = bit % 32;
    unsigned x = HPSV(r_status)[w];
    HPSV(r_status)[w] = v ? (x | (1u << b)) : (x & ~(1u << b));
}
static void field(int lo, int w, int v) { for (int i = 0; i < w; i++) set_status(lo + i, (v >> i) & 1); }

// the image's byte stream through the ioctl port, `stride` clk_sys clocks to a byte, held off by ioctl_wait
static void download(const std::vector<unsigned char> &img, int stride) {
    HPSV(r_index) = 0; HPSV(r_addr) = 0; HPSV(r_download) = 1; run_sys(8);
    for (size_t i = 0; i < img.size(); i++) {
        long guard = 0;
        while (HPSV(r_wait_seen) && guard++ < 1000000) run_sys(1);
        HPSV(r_addr) = i; HPSV(r_dout) = img[i]; HPSV(r_wr) = 1; run_sys(1);
        HPSV(r_wr) = 0; run_sys(stride - 1);
    }
    run_sys(40);
    HPSV(r_download) = 0; run_sys(8);
}

// where an image word lands in the SDRAM (mirrors target/mister/mcatadv_mem.sv)
static int sd_word(uint32_t wa) {
    if (wa < 0x80000) return wa;
    if (wa < 0xA0000) return 0x580000 + (wa - 0x80000);        // Z80
    if (wa >= 0x5A0000) return -2;                             // the configuration bytes and beyond
    if (wa >= 0x320000 && wa < 0x520000) {
        uint32_t w = wa & 63;
        uint32_t p = ((w >> 5) & 1) << 5 | ((w >> 3) & 1) << 4 | ((w >> 2) & 1) << 3 | ((w >> 1) & 1) << 2 | ((w >> 4) & 1) << 1 | (w & 1);
        return ((wa & ~63u) | p) - 0x20000;
    }
    return wa - 0x20000;
}

static unsigned long long fnv(const std::vector<unsigned> &v, int rows, int w) {
    unsigned long long h = 1469598103934665603ull;
    auto mix = [&](unsigned x) { for (int i = 0; i < 4; i++) { h ^= (x >> (8 * i)) & 255; h *= 1099511628211ull; } };
    mix(rows); mix(w);
    for (unsigned x : v) mix(x);
    return h;
}
static void write_ppm(const char *path, const std::vector<unsigned> &px, int w, int h) {
    FILE *f = fopen(path, "wb"); if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int i = 0; i < w * h; i++) { unsigned v = i < (int)px.size() ? px[i] : 0; fputc((v >> 16) & 255, f); fputc((v >> 8) & 255, f); fputc(v & 255, f); }
    fclose(f);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: %s <image.rom> <frames> <out-prefix>\n", argv[0]); return 2; }
    int frames = atoi(argv[2]); const char *pre = argv[3];
    std::vector<unsigned char> img;
    {   FILE *f = fopen(argv[1], "rb"); if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
        fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET); img.resize(n);
        if (fread(img.data(), 1, n, f) != (size_t)n) { fprintf(stderr, "short image\n"); return 1; } fclose(f); }
    // LEN=<bytes>: load only the first part of the image (a quick test of the loading logic; the checks cover that part)
    if (getenv("LEN")) { long n = atol(getenv("LEN")) & ~7L; if (n > 0 && n < (long)img.size()) img.resize(n); }
    const long IMG_LEN = (long)img.size();

    dut = new Vtb_emu_top;
    const bool direct = env_int("DIRECT", 0);
    dut->HDMI_WIDTH  = env_int("HW", direct ? 0 : 1920);          // the scaler's output size (0 x 0 with direct video)
    dut->HDMI_HEIGHT = env_int("HH", direct ? 0 : 1080);
    dut->RESET = 1; run_sys(40); dut->RESET = 0;

    // OSD options (MCatAdv.sv's CONF_STR): overlay [21], Orientation [8:7], Scandoubler Fx [5:3], Scale [34:32], Aspect ratio
    // [122:121], CRT Adjust on [40], H-Size [45:41], H-Position [52:46], V-Shift [57:53] (values as the OSD menu counts them)
    if (env_int("OVL", 1)) set_status(21, 1);
    if (getenv("ORIENT")) field(7, 2, env_int("ORIENT", 0));
    if (getenv("FX")) field(3, 3, env_int("FX", 0));
    if (getenv("SCALE")) field(32, 3, env_int("SCALE", 0));
    if (getenv("AR")) field(121, 2, env_int("AR", 0));
    if (env_int("CRT", 0)) set_status(40, 1);
    if (getenv("HSIZE")) { int v = env_int("HSIZE", 0); field(41, 5, v >= 0 ? v : 25 + v); }
    if (getenv("HPOS"))  { int v = env_int("HPOS", 0);  field(46, 7, v >= 0 ? v : 89 + v); }
    if (getenv("VSHIFT")) { int v = env_int("VSHIFT", 0); field(53, 5, v >= 0 ? v : 27 + v); }
    if (env_int("FSD", 0)) HPSV(r_fsd) = 1;                       // forced_scandoubler (MiSTer.ini)
    if (direct) HPSV(r_direct) = 1;
    run_sys(2000);                                                // PLL stand-ins lock, SDRAM init

    // PRE=<frames>: let the video run that long before the load (with ORIENT=2 the picture is being rotated into the DDR3 frame
    // buffer by then: the load must stop those writes while it owns the port, and they must resume after it)
    if (env_int("PRE", 0)) {
        unsigned long long g = 0; int pre = env_int("PRE", 0);
        while (frames_done < pre && g++ < 8000000000ull) step();
        printf("%d frames before the load; FB_EN %u, screen_rotate writes to the DDR3 so far: %llu\n", frames_done, (unsigned)dut->FB_EN,
               (unsigned long long)dut->rootp->tb_emu_top__DOT__ddr__DOT__rot_writes);
    }
    bool fast = env_int("FAST", 0);
    printf("up after %llu clk_sys clocks; loading %ld bytes %s\n", sclk, IMG_LEN, fast ? "by fast load (the DDR3 replay)" : "streamed through the ioctl port");
    unsigned long long t0 = sclk;
    unsigned long long rot_before = dut->rootp->tb_emu_top__DOT__ddr__DOT__rot_writes;
    if (fast) {
        auto &dd = dut->rootp->tb_emu_top__DOT__ddr__DOT__mem;
        const size_t FLB = 0x400000;                              // beats in the client's window: byte 0x32000000
        for (size_t i = 0; i < (size_t)IMG_LEN / 8; i++) {
            unsigned long long v = 0;
            for (int b = 7; b >= 0; b--) v = (v << 8) | img[i * 8 + b];
            dd[FLB + i] = v;
        }
        // start with ioctl_addr = the image's length, no bytes, end (hps_io counts one more at the end)
        auto start_fast = [&]() {
            HPSV(r_index) = 0; HPSV(r_addr) = IMG_LEN; HPSV(r_download) = 1; run_sys(64);
            HPSV(r_addr) = IMG_LEN + 1; HPSV(r_download) = 0;
        };
        start_fast();
        if (env_int("RESTART", 0)) {
            // RESTART=1: a new (streamed) download begins part-way through the replay, as when another game is chosen; its
            // first bytes go through, and then a fast load is started again and must complete as if nothing had happened
            run_sys(150000);
            printf("restart: a streamed download interrupts the replay (fast_dl %u, loader busy %u)\n", (unsigned)EMUV(fast_dl), (unsigned)EMUV(dl_busy));
            std::vector<unsigned char> head(img.begin(), img.begin() + 4096);
            download(head, 4);
            printf("  the streamed 4096 bytes are through (fast_dl %u); starting the fast load again\n", (unsigned)EMUV(fast_dl));
            run_sys(2000);
            start_fast();
        }
        unsigned long long t1 = sclk; long guard = 0; const long GUARD = 300000000;
        unsigned long long rot_mid = dut->rootp->tb_emu_top__DOT__ddr__DOT__rot_writes;
        int pe_mid = (int)dut->rootp->tb_emu_top__DOT__ddr__DOT__protocol_errors;
        while (EMUV(fast_dl) && guard++ < GUARD) run_sys(1);
        unsigned long long rot_after = dut->rootp->tb_emu_top__DOT__ddr__DOT__rot_writes;
        int pe_after = (int)dut->rootp->tb_emu_top__DOT__ddr__DOT__protocol_errors;
        printf("fast load: the image replayed from the DDR3 in %llu clk_sys clocks (%.3f s at 96 MHz)\n", sclk - t1, (sclk - t1) / 96e6);
        printf("  screen_rotate writes to the DDR3 during the load: %llu (before the download's start: %llu)\n", rot_after - rot_mid, rot_mid - rot_before);
        printf("  DDR protocol errors during the load: %d\n", pe_after - pe_mid);
        if (pe_after != pe_mid) { printf("  FAIL: the loader's DDR3 commands broke the protocol\n"); errors++; }
        if (guard >= GUARD) { printf("  FAIL: the replay did not finish\n"); errors++; }
        if (rot_after != rot_mid) { printf("  FAIL: screen_rotate wrote while the DDR3 was the loader's\n"); errors++; }
        run_sys(8);
    } else {
        download(img, 4);
        printf("image loaded in %llu clk_sys clocks (%.3f s at 96 MHz)\n", sclk - t0, (sclk - t0) / 96e6);
    }
    run_sys(4000);
    {   // the loader's work: every word of the image where the memory's ports expect it
        auto &sd = dut->rootp->tb_emu_top__DOT__chip__DOT__mem;
        unsigned long long words = 0, bad = 0;
        for (size_t wa = 0; wa < (size_t)IMG_LEN / 2; wa++) {
            int sw = sd_word((uint32_t)wa);
            if (sw < 0) continue;
            unsigned v = img[wa * 2] | (img[wa * 2 + 1] << 8);
            words++;
            if (sd[sw] != v) { if (bad < 6) printf("  SDRAM word %06x: %04x, expected %04x\n", sw, (unsigned)sd[sw], v); bad++; }
        }
        printf("loader check: %llu words of the image compared with the SDRAM chip, %llu wrong\n", words, bad);
        if (bad) { printf("  FAIL: the loaded image is not where the ports read it\n"); errors++; }
        if (IMG_LEN < 0xB40010) {
            printf("configuration check skipped (the image is cut short with LEN); machine in reset: %u, fast_dl %u\n", (unsigned)EMUV(mc_rst), (unsigned)EMUV(fast_dl));
        } else {
            const unsigned char *cfg = img.data() + 0xB40000;
            unsigned want_bg0 = cfg[1] | (cfg[2] << 8), want_bg1 = cfg[3] | (cfg[4] << 8);
            unsigned got_game = EMUV(nost), got_bg0 = EMUV(cfg_bg0), got_bg1 = EMUV(cfg_bg1);
            printf("configuration: game %u (image %u), BG0 tiles %u (%u), BG1 tiles %u (%u); machine in reset: %u, fast_dl %u\n",
                   got_game, cfg[0] & 1u, got_bg0, want_bg0, got_bg1, want_bg1, (unsigned)EMUV(mc_rst), (unsigned)EMUV(fast_dl));
            if (got_game != (cfg[0] & 1u) || got_bg0 != want_bg0 || got_bg1 != want_bg1) { printf("  FAIL: the configuration the loader captured\n"); errors++; }
        }
    }

    // JOYTEST=1: the controller decoding, for both games' button layouts (the MRA's <buttons> order is the joystick bits from 4 on):
    //   Magical Cat Adventure 4 Fire, 5 Jump, 6 Start, 7 Coin;  Nostradamus 4 Shot, 5 Start, 6 Coin; nothing else is wired.
    // Each joystick bit is set alone and the board's P1 / P2 inputs (active low) are read back.
    if (env_int("JOYTEST", 0)) {
        auto &cg = dut->rootp->tb_emu_top__DOT__u_emu__DOT__u_mem__DOT__cfg_game;
        for (int game = 0; game < 2; game++) {
            cg = game;
            const unsigned idle1 = game ? 0xF7FF : 0xFFFF;                  // Nostradamus: P1 bit 11 must read 0
            // joystick bit -> the P1 bit it pulls low (0 = none)
            const int want[2][16] = {
                {-1, -1, -1, -1, 4, 5, 7, 8, 0, 0, 0, 0, 0, 0, 0, 0},       // bits 0-3 are the directions, below
                {-1, -1, -1, -1, 4, 7, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0}};
            const int dirbit[4] = {3, 2, 1, 0};                              // joystick 0 right, 1 left, 2 down, 3 up -> P1 bits 3, 2, 1, 0
            int bad = 0;
            for (int pl = 0; pl < 2; pl++) {
                for (int b = 0; b < 12; b++) {
                    if (pl == 0) { HPSV(r_joy0) = 1u << b; HPSV(r_joy1) = 0; } else { HPSV(r_joy0) = 0; HPSV(r_joy1) = 1u << b; }
                    run_sys(6);
                    unsigned p1 = (unsigned)EMUV(p1_in), p2 = (unsigned)EMUV(p2_in);
                    unsigned got = pl == 0 ? (idle1 ^ p1) : (0xFFFFu ^ p2);       // the bits pulled low
                    unsigned other = pl == 0 ? (0xFFFFu ^ p2) : (idle1 ^ p1);     // nothing may move on the other player's port
                    unsigned exp = 0;
                    if (b < 4) exp = 1u << dirbit[b];
                    else if (want[game][b] > 0) exp = 1u << want[game][b];             // (player 2's bits are player 1's)
                    if (got != exp || other != 0) { bad++; printf("  JOY FAIL: game %d player %d joystick bit %d: pulled low %04x (expected %04x), other port %04x\n", game, pl + 1, b, got, exp, other); }
                }
            }
            printf("controller decoding, %s (cfg_game %d): %s\n", game ? "Nostradamus: Shot, Start, Coin" : "Magical Cat Adventure: Fire, Jump, Start, Coin", game, bad ? "FAIL" : "every joystick bit does what the layout says, and the service / test inputs are not reachable");
            if (bad) errors++;
        }
        HPSV(r_joy0) = 0; HPSV(r_joy1) = 0; cg = 0; run_sys(6);
    }

    // frames after the load
    if (env_int("HOLD", 1)) set_status(0, 1);                     // the OSD's Reset: the machine is held, so the overlay is a still picture
    int start = frames_done, target = start + frames;
    unsigned long long guard = 0;
    while (frames_done < target && guard++ < 8000000000ull) step();
    if (frames_done < target) {
        printf("  STALL: %d of %d frames; VGA_VS edges %llu, VGA_HS edges %llu, DE rises %llu\n", frames_done - start, frames, n_vs, n_hs, n_de);
        errors++;
    }
    printf("%d frames after the load; the last frame: %d rows of %d pixels\n", frames_done - start, rows_last, width_last);
    printf("frame period %llu clk_vid clocks (the 15 kHz raster is 448 x 260 x 8 = %d)\n", frame_period, 448 * 260 * 8);
    printf("geometry (last frame): %d rows with picture, %d lines a frame; first row %ld clocks after the vsync pulse (%.3f lines);"
           " rows start %ld..%ld clocks after hsync, %ld..%ld clocks wide\n",
           geo_rows, geo_lines, geo_first, geo_first / (448.0 * 8), geo_smin, geo_smax, geo_wmin, geo_wmax);
    printf("picture hash %016llx\n", fnv(px_last, rows_last, width_last));
    {   // the size the core asks the scaler for
        unsigned ax = dut->VIDEO_ARX, ay = dut->VIDEO_ARY;
        if ((ax & 0x1000) || (ay & 0x1000)) printf("scaler: integer size %u x %u (VIDEO_ARX %04x, VIDEO_ARY %04x) for the scaler's %u x %u\n", ax & 0xfff, ay & 0xfff, ax, ay, (unsigned)dut->HDMI_WIDTH, (unsigned)dut->HDMI_HEIGHT);
        else printf("scaler: aspect ratio %u:%u (VIDEO_ARX %04x, VIDEO_ARY %04x)\n", ax, ay, ax, ay);
        printf("menu mask the core computes: %04x (bit 0 direct video, bit 1 picture turned, bit 2 CRT Adjust off)\n", (unsigned)HPSV(r_mask_seen));
    }
    {
        unsigned long long rw = dut->rootp->tb_emu_top__DOT__ddr__DOT__rot_writes;
        printf("rotated frame buffer: FB_EN %u, %u x %u; screen_rotate writes to the DDR3 so far: %llu; rotating: %s\n", (unsigned)dut->FB_EN,
               (unsigned)dut->FB_WIDTH, (unsigned)dut->FB_HEIGHT, rw, EMUV(no_rotate) ? "no" : "yes");
        // after a load that began with the picture already being rotated (PRE=<frames>, ORIENT=2) the writes must have resumed
        if (env_int("PRE", 0) && !EMUV(no_rotate) && rw <= rot_before) { printf("  FAIL: screen_rotate did not write again after the load\n"); errors++; }
    }
    {   char p[512]; snprintf(p, sizeof p, "%s_scaler.ppm", pre); write_ppm(p, px_last, width_last, rows_last); }
    {   // (the framework's screen_rotate never looks at DDRAM_BUSY: while it rotates, a write that meets the model's random BUSY
        // is counted here, as it would be on any core that uses it; only a run without rotation must be clean)
        int pe = (int)dut->rootp->tb_emu_top__DOT__ddr__DOT__protocol_errors;
        printf("DDR protocol errors in the whole run: %d%s\n", pe, EMUV(no_rotate) ? "" : " (screen_rotate ignores DDRAM_BUSY; see tb_emu.cpp)");
        if (pe && EMUV(no_rotate)) errors++;
    }
    printf("%s\n", errors ? "RESULT: FAIL" : "RESULT: ok");
    delete dut;
    return errors ? 1 : 0;
}
