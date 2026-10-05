// Sound board on the real memory system: tb_sndsys <game.rom> <seconds> <out.wav> [cmd@ms ...]
//   env TRAFFIC=0..255 busyness of the other SDRAM clients (default 64), YMLOG=<file> the YM writes, NOLOAD=1 skips nothing
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>
#include "Vtb_sndsys_top.h"
#include "Vtb_sndsys_top__Dpi.h"
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
    if (wa < 0xA0000) return 0x580000 + (wa - 0x80000);
    if (wa >= 0x5A0000) return -2;
    if (wa >= 0x320000 && wa < 0x520000) {
        uint32_t w = wa & 63;
        uint32_t p = ((w >> 5) & 1) << 5 | ((w >> 3) & 1) << 4 | ((w >> 2) & 1) << 3 | ((w >> 1) & 1) << 2 | ((w >> 4) & 1) << 1 | (w & 1);
        return ((wa & ~63u) | p) - 0x20000;
    }
    return wa - 0x20000;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_sndsys game.rom seconds out.wav [cmd@ms ...]\n"); return 2; }
    auto img = load_file(argv[1]);
    double secs = atof(argv[2]);
    const char* out = argv[3];
    struct Ev { double ms; int cmd; };
    std::vector<Ev> evs;
    for (int i = 4; i < argc; i++) { int c; double m; if (sscanf(argv[i], "%d@%lf", &c, &m) == 2) evs.push_back({m, c}); }
    int traffic = getenv("TRAFFIC") ? atoi(getenv("TRAFFIC")) : 64;
    FILE* ylog = getenv("YMLOG") ? fopen(getenv("YMLOG"), "w") : nullptr;

    Vtb_sndsys_top* t = new Vtb_sndsys_top;
    svSetScope(svGetScopeFromName("TOP.tb_sndsys_top"));
    t->traffic = 0; t->dl_start = 0; t->dl_we = 0; t->dl_addr = 0; t->dl_data = 0; t->cmd = 0; t->cmd_wr = 0;
    t->clk = 0; t->init = 1; t->rst = 1;
    // clk 96 MHz; clk_snd 48 MHz from the same PLL: rises with every second clk rise and falls with the ones in between
    int par = 0;
    auto rise = [&]() { t->clk = 1; t->clk_snd = (par == 0); par ^= 1; t->eval(); };
    auto fall = [&]() { t->clk = 0; t->eval(); };
    auto cyc = [&](int n) { for (int i = 0; i < n; i++) { rise(); fall(); } };
    cyc(200);
    t->init = 0;
    for (long g = 0; !t->mem_ready && g < 100000; g++) cyc(1);
    cyc(100);

    // load the image through the RTL loader
    t->dl_start = 1; cyc(2); t->dl_start = 0;
    size_t n = img.size();
    for (size_t i = 0; i < n; ) {
        if (!t->dl_wait) { t->dl_we = 1; t->dl_addr = i; t->dl_data = img[i]; i++; }
        else t->dl_we = 0;
        cyc(1);
        t->dl_we = 0;
        cyc(2);
    }
    while (t->dl_busy) cyc(1);
    cyc(100);
    long bad = 0, words = n / 2;
    for (long wa = 0; wa < words; wa++) {
        int sw = sd_word(wa);
        if (sw < 0) continue;
        uint16_t w = img[2 * wa] | (img[2 * wa + 1] << 8);
        if ((uint16_t)tb_sdram_read(sw) != w) { if (bad < 10) fprintf(stderr, "mismatch at image word %lx (sdram %x): %04x vs %04x\n", wa, sw, (uint16_t)tb_sdram_read(sw), w); bad++; }
    }
    fprintf(stderr, "image loaded: %ld of %ld words differ; game %d tiles %d %d\n", bad, words, (int)t->cfg_game, (int)t->cfg_bg0, (int)t->cfg_bg1);

    // run
    t->traffic = traffic;
    t->rst = 0;
    uint64_t total = (uint64_t)(secs * 96e6);
    std::vector<int16_t> audio, adp;
    long nz = 0, ymw = 0, pcmreq = 0, pcm_bad = 0, lat_max = 0, lat_sum = 0, lat_over = 0, nmi = 0;
    bool pym = false, pq = false, pn = false, pv = false;
    long since = 0;
    size_t ei = 0;
    for (uint64_t c = 0; c < total; c++) {
        rise();
        double ms = c / 96e3;
        t->cmd_wr = 0;
        if (ei < evs.size() && ms >= evs[ei].ms) { t->cmd = evs[ei].cmd; t->cmd_wr = 1; fprintf(stderr, "t=%.1f ms: command %02x\n", ms, evs[ei].cmd); ei++; }
        if (t->snd_valid && !pv) { audio.push_back(t->snd_l); adp.push_back((int16_t)t->adpcma_dbg); if (t->snd_l) nz++; } pv = t->snd_valid;
        if (t->ym_wr && !pym) { ymw++; if (ylog) fprintf(ylog, "%.1f %d %02x\n", ms, t->ym_a, t->ym_d); } pym = t->ym_wr;
        if (t->nmi_pend && !pn) nmi++; pn = t->nmi_pend;
        if (t->pcm_req_o && !pq) { pcmreq++; since = 0; } pq = t->pcm_req_o;
        if (t->pcm_req_o) since++;
        if (t->pcm_ack_o) {
            lat_sum += since; if (since > lat_max) lat_max = since; if (since > 144) lat_over++;     // 1.5 us
            uint32_t pa = 0xA40000 + t->pcm_addr_o;
            if (img[pa] != t->pcm_q_o) { if (pcm_bad < 5) fprintf(stderr, "PCM byte at %05x: %02x vs %02x\n", t->pcm_addr_o, t->pcm_q_o, img[pa]); pcm_bad++; }
        }
        fall();
    }
    fprintf(stderr, "%zu samples, %ld non-zero; YM writes %ld, NMIs %ld; PCM reads %ld (wrong byte %ld, latency avg %.1f max %ld clocks, %ld over 1.5 us)\n",
            audio.size(), nz, ymw, nmi, pcmreq, pcm_bad, pcmreq ? (double)lat_sum / pcmreq : 0.0, lat_max, lat_over);
    if (getenv("ADPLOG")) { FILE* g = fopen(getenv("ADPLOG"), "wb"); fwrite(adp.data(), 2, adp.size(), g); fclose(g); }
    FILE* f = fopen(out, "wb");
    uint32_t nb = audio.size() * 2, rate = 55555, br = rate * 2;
    uint16_t one = 1, bits = 16, ba = 2, fmt = 1; uint32_t sixteen = 16, riff = 36 + nb;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&sixteen, 4, 1, f);
    fwrite(&fmt, 2, 1, f); fwrite(&one, 2, 1, f); fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f); fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&nb, 4, 1, f); fwrite(audio.data(), 2, audio.size(), f);
    fclose(f);
    delete t;
    return 0;
}
