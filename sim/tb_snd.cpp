// Sound board bench driver: tb_snd <out.wav> <seconds> [cmd@ms ...]   e.g. tb_snd a.wav 6 239@50 31@1000
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <algorithm>
#include "Vtb_snd_top.h"
#include "verilated.h"
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const char* out = argc > 1 ? argv[1] : "snd.wav";
    double secs = argc > 2 ? atof(argv[2]) : 3.0;
    struct Ev { double ms; int cmd; };
    std::vector<Ev> evs;
    for (int i = 3; i < argc; i++) { int c; double m; if (sscanf(argv[i], "%d@%lf", &c, &m) == 2) evs.push_back({m, c}); }
    Vtb_snd_top* t = new Vtb_snd_top;
    t->clk = 0; t->rst = 1; t->cmd_wr = 0; t->cmd = 0; t->nost = getenv("NOST") ? 1 : 0;
    for (int i = 0; i < 2 * (getenv("RST0_CLKS") ? atoi(getenv("RST0_CLKS")) : 50); i++) { t->clk = !t->clk; t->eval(); }
    t->rst = 0;
    uint64_t total = (uint64_t)(secs * 16e6);
    std::vector<int16_t> audio;
    int div = 0; long nz = 0, ymw = 0, z80rd = 0, nmi = 0, pcmreq = 0; bool pym = false, pn = false, pq = false;
    size_t ei = 0;
    int pans = 0;
    static long awin[200], fmwin[200];
    std::vector<int16_t> adp;                           // the ADPCM-A part of the mix (ADPLOG=<file>: raw int16)
    double rstpulse_ms = getenv("RSTPULSE_MS") ? atof(getenv("RSTPULSE_MS")) : -1;
    FILE* ylog = getenv("YMLOG") ? fopen(getenv("YMLOG"), "w") : nullptr;
    for (uint64_t c = 0; c < total; c++) {
        t->clk = 1; t->eval();
        double ms = c / 16e3;
        t->cmd_wr = 0;
        if (rstpulse_ms >= 0) {          // a short reset in the middle of the run, like the watchdog's (255 clocks of 96 MHz = 42 of 16 MHz)
            if (ms >= rstpulse_ms && ms < rstpulse_ms + 42 / 16e3) t->rst = 1; else t->rst = 0;
        }
        if (ei < evs.size() && ms >= evs[ei].ms) { t->cmd = evs[ei].cmd; t->cmd_wr = 1; fprintf(stderr, "t=%.1f ms: command %02x\n", ms, evs[ei].cmd); ei++; }
        if (++div == 288) { div = 0; audio.push_back(t->snd_l); if (t->snd_l) nz++;
            adp.push_back((int16_t)t->adpcma_dbg);
            int a = (int16_t)t->adpcma_dbg; if (a < 0) a = -a;
            int w = (int)(ms / 100.0); if (w < 200) { awin[w] += a; fmwin[w] += abs((int)(int16_t)t->snd_l); } }
        if (t->ym_wr && !pym) { ymw++; if (ylog) fprintf(ylog, "%.1f %d %02x\n", ms, t->ym_a, t->ym_d); } pym = t->ym_wr;
        if ((int)t->ans != pans) { fprintf(stderr, "t=%.1f ms: answer latch %02x\n", ms, (int)t->ans); pans = t->ans; }
        if (t->nmi_pend && !pn) nmi++; pn = t->nmi_pend;
        if (t->pcm_req_o && !pq) pcmreq++; pq = t->pcm_req_o;
        if (t->z80_rd) z80rd++;
        t->clk = 0; t->eval();
    }
    if (getenv("WINSTAT")) for (int w = 0; w < (int)(secs * 10); w++) fprintf(stderr, "  %4d-%4d ms: mean |ADPCM-A| %7.1f   mean |output| %7.1f\n", w * 100, w * 100 + 100, awin[w] / 5555.0, fmwin[w] / 5555.0);
    fprintf(stderr, "%zu samples, %ld non-zero; YM writes %ld, NMIs %ld, PCM reads %ld, Z80 memory reads %ld\n", audio.size(), nz, ymw, nmi, pcmreq, z80rd);
    if (getenv("ADPLOG")) { FILE* g = fopen(getenv("ADPLOG"), "wb"); fwrite(adp.data(), 2, adp.size(), g); fclose(g); }
    FILE* f = fopen(out, "wb");
    uint32_t n = audio.size() * 2, rate = 55555, br = rate * 2;
    uint16_t one = 1, bits = 16, ba = 2, fmt = 1; uint32_t sixteen = 16, riff = 36 + n;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&sixteen, 4, 1, f);
    fwrite(&fmt, 2, 1, f); fwrite(&one, 2, 1, f); fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f); fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&n, 4, 1, f); fwrite(audio.data(), 2, audio.size(), f);
    fclose(f);
    delete t;
    return 0;
}
