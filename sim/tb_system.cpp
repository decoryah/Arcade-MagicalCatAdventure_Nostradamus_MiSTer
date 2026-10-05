// Whole-machine bench driver.
//   tb_system <game.rom> <frames> <out-prefix> [+dump=<dump-prefix>] [+load=rtl] [+hold] [+trace]
// Writes <out>.fNNN.ppm (every frame after the first), <out>.wav, and a status line a frame.
//   +dump=P  preload the video RAMs from P_*.hex (tb_main_top's dumps) and keep the CPU in reset
//   +load=rtl push the image through the RTL loader instead of preloading the SDRAM
//   +hold    keep the CPU in reset without a dump
//   +fast    shorten the watchdog to 3,000,000 clocks until it has fired once (the first boot waits for it)
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include "Vtb_system_top.h"
#include "Vtb_system_top__Dpi.h"
#include "verilated.h"
#include "svdpi.h"

static std::vector<uint8_t> load_file(const char* p) {
    std::vector<uint8_t> v;
    FILE* f = fopen(p, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", p); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    v.resize(n);
    if (fread(v.data(), 1, n, f) != (size_t)n) exit(2);
    fclose(f);
    return v;
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

static void write_ppm(const char* path, const uint8_t* rgb, int w, int h) {
    FILE* f = fopen(path, "wb");
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(rgb, 1, w * h * 3, f);
    fclose(f);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_system game.rom frames out-prefix [+dump=..]\n"); return 2; }
    const char* rom = argv[1];
    int frames = atoi(argv[2]);
    std::string outp = argv[3];
    bool dump_mode = false, load_rtl = false, hold = false, fast = false, trace = false;
    int coin_frame = -1;
    for (int i = 4; i < argc; i++) {
        if (!strncmp(argv[i], "+dump=", 6)) dump_mode = true;
        if (!strcmp(argv[i], "+load=rtl")) load_rtl = true;
        if (!strcmp(argv[i], "+hold")) hold = true;
        if (!strcmp(argv[i], "+fast")) fast = true;
        if (!strcmp(argv[i], "+trace")) trace = true;
        if (!strncmp(argv[i], "+coin=", 6)) coin_frame = atoi(argv[i] + 6);
    }
    auto img = load_file(rom);
    Vtb_system_top* t = new Vtb_system_top;
    svSetScope(svGetScopeFromName("TOP.tb_system_top"));

    // inputs
    const bool nost = img.size() > 0xB40000 && (img[0xB40000] & 1);      // Nostradamus: P1 bit 11 reads 0, the DIP switches' low bytes read 0
    const uint16_t p1base = nost ? 0xF7FF : 0xFFFF;
    t->p1_in = p1base; t->p2_in = 0xFFFF; t->dsw1_in = t->dsw2_in = nost ? 0xFF00 : 0xFFFF;
    t->wdog_limit = fast ? 3000000 : 288000000;
    t->dl_start = 0; t->dl_we = 0; t->dl_addr = 0; t->dl_data = 0;
    t->clk = 0; t->clk_snd = 0; t->clk_vid = 0;
    t->init = 1; t->rst = 1; t->vid_rst = 1;

    // base tick = 1/1344 us: clk (96 MHz) toggles every 7 ticks, clk_vid (28 MHz) every 24
    uint64_t tick = 0;
    auto step = [&]() {
        tick++;
        bool ch = false;
        if (tick % 7 == 0)  { t->clk = !t->clk; ch = true; }
        if (tick % 14 == 7) { t->clk_snd = !t->clk_snd; ch = true; }                  // 48 MHz, rising with every second clk rise
        if (tick % 24 == 0) { t->clk_vid = !t->clk_vid; ch = true; }
        if (ch) t->eval();
    };
    auto run_sys_cycles = [&](int n) { for (int i = 0; i < n; ) { bool before = t->clk; step(); if (t->clk && !before) i++; } };

    // reset the controller
    run_sys_cycles(200);
    t->init = 0;
    while (!t->mem_ready) step();
    run_sys_cycles(100);

    if (!load_rtl) {
        // preload the chip and the Z80 ROM behind the loader's back
        long words = img.size() / 2;
        for (long wa = 0; wa < words; wa++) {
            int sw = sd_word(wa);
            uint16_t w = img[2 * wa] | (img[2 * wa + 1] << 8);
            if (sw >= 0) tb_sdram_write(sw, w);
        }
        const uint8_t* cfg = img.data() + 0xB40000;
        bool spr0_blank = true; for (int i = 0; i < 128; i++) if (img[0x140000 + i]) spr0_blank = false;
        tb_cfg(cfg[0] & 1, cfg[1] | cfg[2] << 8, cfg[3] | cfg[4] << 8, spr0_blank);
        fprintf(stderr, "image preloaded (%zu bytes)\n", img.size());
    } else {
        t->dl_start = 1; run_sys_cycles(2); t->dl_start = 0;
        size_t n = img.size();
        for (size_t i = 0; i < n; ) {
            if (!t->dl_wait) { t->dl_we = 1; t->dl_addr = i; t->dl_data = img[i]; i++; }
            else t->dl_we = 0;
            run_sys_cycles(1);
            t->dl_we = 0;
            run_sys_cycles(2);
        }
        while (t->dl_busy) run_sys_cycles(1);
        run_sys_cycles(100);
        fprintf(stderr, "image loaded through the RTL loader\n");
        // read back and compare with what the layout says
        long bad = 0, words = n / 2;
        for (long wa = 0; wa < words; wa++) {
            int sw = sd_word(wa);
            if (sw < 0) continue;
            uint16_t w = img[2 * wa] | (img[2 * wa + 1] << 8);
            if ((uint16_t)tb_sdram_read(sw) != w) { if (bad < 10) fprintf(stderr, "mismatch at image word %lx (sdram %x): %04x vs %04x\n", wa, sw, (uint16_t)tb_sdram_read(sw), w); bad++; }
        }
        fprintf(stderr, "loader check: %ld of %ld words differ\n", bad, words);
    }

    bool cpu_off = dump_mode || hold;
    t->rst = cpu_off ? 1 : 0;
    t->vid_rst = 0;
    run_sys_cycles(10);

    // run
    std::vector<uint8_t> fb(320 * 224 * 3, 0);
    std::vector<int16_t> audio;
    FILE* tf = trace ? fopen((outp + ".trace").c_str(), "w") : nullptr;
    int col = 0, row = 0, nframe = 0, saved = 0;
    bool prev_vsync = false, prev_hblank = true, prev_vblank = true, vis_in_row = false;
    long ovr0 = 0, ovr1 = 0, ovrs = 0, irq = 0;
    bool po0 = false, po1 = false, pos = false, pirq = false, pwd = false;
    bool pclk = t->clk, pvid = t->clk_vid;
    long wd = 0;
    int audio_div = 0;
    long n_snd = 0, n_ym = 0, n_z80 = 0, n_nmi = 0, n_m1 = 0, n_zw = 0; bool pym = false, pnmi = false, pm1 = false, pzw = false;
    long run_s = 0, run_t0 = 0, run_t1 = 0, max_s = 0, max_t0 = 0, max_t1 = 0;
    auto write_wav = [&]() {
        if (audio.empty()) return;
        FILE* f = fopen((outp + ".wav").c_str(), "wb");
        uint32_t n = audio.size() * 2, rate = 55555, br = rate * 2;
        uint16_t one = 1, bits = 16, ba = 2, fmt = 1; uint32_t sixteen = 16, riff = 36 + n;
        fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&sixteen, 4, 1, f);
        fwrite(&fmt, 2, 1, f); fwrite(&one, 2, 1, f); fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f); fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f);
        fwrite("data", 1, 4, f); fwrite(&n, 4, 1, f); fwrite(audio.data(), 2, audio.size(), f);
        fclose(f);
    };
    uint64_t guard = (uint64_t)(frames + 3) * 1600000ULL * 14;
    while (nframe < frames + 1 && tick < guard) {
        {   // scripted coin and start (+coin=<frame>)
            uint16_t in = p1base;
            if (coin_frame >= 0 && nframe >= coin_frame && nframe < coin_frame + 6) in &= ~0x0100;
            if (coin_frame >= 0 && nframe >= coin_frame + 30 && nframe < coin_frame + 36) in &= ~0x0080;
            t->p1_in = in;
        }
        step();
        if (t->clk && !pclk) {      // machine clock rising edge
            if (++audio_div == 1728) { audio_div = 0; audio.push_back(t->snd_l); }       // 96 MHz / 1728 = 55.5 kHz, the YM2610's rate
            if (t->dbg_ovr_t0 && !po0) ovr0++;  po0 = t->dbg_ovr_t0;
            if (t->dbg_ovr_t1 && !po1) ovr1++;  po1 = t->dbg_ovr_t1;
            if (t->dbg_ovr_s && !pos)  ovrs++;  pos = t->dbg_ovr_s;
            if (t->dbg_irq && !pirq) irq++;     pirq = t->dbg_irq;
            if (t->trc_stb && !t->trc_rw && ((uint32_t)t->dbg_addr << 1) == 0xc00000) { n_snd++; if (n_snd <= 40) fprintf(stderr, "  68000 sound command %02x (frame %d)\n", t->trc_data & 255, nframe); }
            if (t->ym_wr && !pym) n_ym++; pym = t->ym_wr;
            if (t->nmi_pend && !pnmi) n_nmi++; pnmi = t->nmi_pend;
            if (t->z80_m1 && !pm1) n_m1++; pm1 = t->z80_m1;
            if (t->z80_wr && !pzw) n_zw++; pzw = t->z80_wr;
            run_s  = t->busy_s  ? run_s  + 1 : 0; if (run_s  > max_s)  max_s  = run_s;
            run_t0 = t->busy_t0 ? run_t0 + 1 : 0; if (run_t0 > max_t0) max_t0 = run_t0;
            run_t1 = t->busy_t1 ? run_t1 + 1 : 0; if (run_t1 > max_t1) max_t1 = run_t1;
            if (t->dbg_wdog && !pwd) wd++;      pwd = t->dbg_wdog;
            if (tf && t->trc_stb) fprintf(tf, "%llu %c %06x %04x %d%d\n", (unsigned long long)tick, t->trc_rw ? 'R' : 'W', (uint32_t)t->dbg_addr << 1, t->trc_data, (t->trc_be >> 1) & 1, t->trc_be & 1);
            if (t->dbg_halted) { fprintf(stderr, "CPU HALTED\n"); break; }
        }
        pclk = t->clk;
        if (!t->clk_vid && pvid && t->ce_pix) {}      // (clk_vid falling edge handled below)
        if (!t->clk_vid && pvid) {
            // clk_vid falling edge: sample the pixel stream
            if (t->ce_pix) {
                bool hb = t->hblank, vb = t->vblank, vs = t->vsync;
                if (!hb && !vb) {
                    if (col < 320 && row < 224) {
                        uint32_t c = t->rgb;
                        fb[(row * 320 + col) * 3 + 0] = (c >> 16) & 255;
                        fb[(row * 320 + col) * 3 + 1] = (c >> 8) & 255;
                        fb[(row * 320 + col) * 3 + 2] = c & 255;
                    }
                    col++; vis_in_row = true;
                }
                if (hb && !prev_hblank) {}
                if (hb && vis_in_row) { row++; col = 0; vis_in_row = false; }
                if (vb && !prev_vblank) {
                    // a frame has been drawn
                    if (nframe > 0 && row >= 224) {
                        char p[512]; snprintf(p, sizeof p, "%s.f%03d.ppm", outp.c_str(), nframe);
                        write_ppm(p, fb.data(), 320, 224); saved++;
                    }
                    fprintf(stderr, "frame %d: overruns tm0 %ld tm1 %ld spr %ld, irqs %ld, watchdog resets %ld, rows %d, longest line (of 6144 clocks): sprites %ld tm0 %ld tm1 %ld\n", nframe, ovr0, ovr1, ovrs, irq, wd, row, max_s, max_t0, max_t1);
                    if (nframe % 30 == 0) fprintf(stderr, "  sound: %ld 68000 commands, %ld Z80 NMIs, %ld Z80 opcode fetches, %ld Z80 writes, %ld YM writes\n", n_snd, n_nmi, n_m1, n_zw, n_ym);
                    max_s = max_t0 = max_t1 = 0;
                    nframe++;
                    if (nframe % 10 == 0) write_wav();
                    row = 0; col = 0;
                }
                if (!vb) {} else { row = 0; col = 0; vis_in_row = false; }
                prev_hblank = hb; prev_vblank = vb; prev_vsync = vs;
            }
        }
        pvid = t->clk_vid;
    }
    // sound
    write_wav();
    if (!audio.empty()) {
        long nz = 0; for (auto s : audio) if (s) nz++;
        fprintf(stderr, "audio: %zu samples, %ld non-zero\n", audio.size(), nz);
    }
    if (tf) fclose(tf);
    fprintf(stderr, "%d frames saved\n", saved);
    delete t;
    return 0;
}
