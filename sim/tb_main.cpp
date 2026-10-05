// CPU-side bring-up: boots the real program and logs the 68000's bus cycles.
//   tb_main <frames> <trace-out> [first-frame-to-trace]
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <map>
#include <string>
#include <vector>
#include <cstring>
#include "Vtb_main_top.h"
#include "verilated.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    int frames = argc > 1 ? atoi(argv[1]) : 10;
    const char* tracef = argc > 2 ? argv[2] : "main.trace";
    int trace_from = argc > 3 ? atoi(argv[3]) : 0;
    std::vector<int> dump_frames;                       // argv[4]: comma separated frames to dump the video RAMs at
    if (argc > 4) { char* s = strdup(argv[4]); for (char* p = strtok(s, ","); p; p = strtok(NULL, ",")) dump_frames.push_back(atoi(p)); }
    Vtb_main_top* t = new Vtb_main_top;
    FILE* tf = fopen(tracef, "w");
    uint64_t cycle = 0;
    const uint64_t frame_clks = 532480;
    uint64_t total = (uint64_t)frames * frame_clks;
    int coin_frame = getenv("COIN") ? atoi(getenv("COIN")) : -1;
    const bool nost = getenv("NOST") != nullptr;      // Nostradamus: P1 bit 11 reads 0, the DIP switches' low bytes read 0
    const uint16_t p1base = nost ? 0xF7FF : 0xFFFF;
    t->p2_in = 0xFFFF; t->p1_in = p1base; t->dsw1_in = t->dsw2_in = nost ? 0xFF00 : 0xFFFF; t->nost = nost;
    if (getenv("DSW1")) t->dsw1_in = (uint16_t)strtol(getenv("DSW1"), nullptr, 16);      // e.g. DSW1=EF00: Nostradamus with the flip screen switch on
    t->reset = 1; t->clk = 0;
    for (int i = 0; i < 40; i++) { t->clk = !t->clk; t->eval(); }
    t->reset = 0;
    std::map<std::string, uint64_t> counts;
    uint64_t nreads = 0, nwrites = 0;
    int wdog = 0;
    for (cycle = 0; cycle < total; cycle++) {
        {
            int fr = (int)(cycle / frame_clks);
            uint16_t in = p1base;
            if (coin_frame >= 0 && fr >= coin_frame && fr < coin_frame + 6) in &= ~0x0100;        // coin 1
            if (coin_frame >= 0 && fr >= coin_frame + 30 && fr < coin_frame + 36) in &= ~0x0080;  // start 1
            t->p1_in = in;
            uint16_t in2 = 0xFFFF;                                                                  // SVC=<frame>[,<frame>...]: SERVICE1 (P2 bit 9) pressed for 4 frames from each
            if (getenv("SVC")) { char* q = strdup(getenv("SVC")); for (char* r = strtok(q, ","); r; r = strtok(NULL, ",")) { int f0 = atoi(r); if (fr >= f0 && fr < f0 + 4) in2 &= ~0x0200; } free(q); }
            t->p2_in = in2;
        }
        t->clk = 1; t->eval();
        if (t->trc_stb) {
            uint32_t a = (uint32_t)t->trc_addr << 1;
            int fr = (int)(cycle / frame_clks);
            if (t->trc_rw) nreads++; else nwrites++;
            if (getenv("TRACE_VIDEO") && !t->trc_rw) {
                bool vr = (a >= 0x200000 && a < 0x300008) || (a >= 0xb00000 && a < 0xb00020) || (a >= 0x401000 && a < 0x401800) || (a >= 0x501000 && a < 0x501800);
                if (vr) fprintf(tf, "V %d %06llu %06x %04x\n", fr,(unsigned long long)(cycle % frame_clks), a, t->trc_data);
            }
            if (fr >= trace_from)
                fprintf(tf, "%llu f%d %c %06x %04x %d%d\n", (unsigned long long)cycle, fr, t->trc_rw ? 'R' : 'W', a, t->trc_data, (t->trc_be >> 1) & 1, t->trc_be & 1);
            char key[32];
            snprintf(key, sizeof key, "%c %02x", t->trc_rw ? 'R' : 'W', a >> 16);
            counts[key]++;
        }
        if (t->snd_cmd_wr_o) fprintf(tf, "%llu SNDCMD %02x\n", (unsigned long long)cycle, t->snd_cmd_o);
        if (t->wdog_kick_o) fprintf(tf, "%llu KICK\n", (unsigned long long)cycle);
        if (t->wdog_reset_o) { wdog++; fprintf(tf, "%llu WATCHDOG\n", (unsigned long long)cycle); }
        if (t->cpu_halted) { fprintf(stderr, "CPU HALTED at cycle %llu\n", (unsigned long long)cycle); break; }
        t->clk = 0; t->eval();
        {   // dump at the start of vertical blanking of the requested frames (the board's frame count)
            int fr = (int)(cycle / frame_clks);
            bool want = false;
            for (int d : dump_frames) if (d == fr && (cycle % frame_clks) == 458800) { want = true; t->dump_tag = d; }
            t->dump = want; if (want) { t->eval(); fprintf(stderr, "dump at frame %d\n", fr); }
        }
        if ((cycle % frame_clks) == frame_clks - 1) {
            fprintf(stderr, "frame %d done: %llu reads %llu writes, %d watchdog resets\n", (int)(cycle / frame_clks),
                    (unsigned long long)nreads, (unsigned long long)nwrites, wdog);
        }
    }
    fprintf(stderr, "bus cycles by region (op, addr[23:16]):\n");
    for (auto& kv : counts) fprintf(stderr, "  %s: %llu\n", kv.first.c_str(), (unsigned long long)kv.second);
    fclose(tf);
    delete t;
    return 0;
}
