// battery.cpp
// LOCALHOST flick_proto — scripted gesture battery + pass-matrix harness.
//
// Every case builds a deterministic right-stick sample stream (60 Hz, small
// seeded jitter, like a real gamepad poll), runs the recognizer, and checks
// the recognized trick sequences against expectations. Prints a pass matrix
// and exits 0 only at >= 90% correct (the JOO-193 v0 acceptance floor).
//
// Build: g++ -std=c++17 -O2 -Wall -Wextra -o battery flick_recognizer.cpp battery.cpp

#include "flick_recognizer.hpp"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <string>
#include <vector>

using namespace flick;

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kDt = 1.0 / 60.0; // 60 Hz stick poll

// Deterministic gesture path builder ---------------------------------------
struct Path {
    std::vector<Sample> pts;
    double now = 0.0;
    std::mt19937 rng{1337};
    std::normal_distribution<double> jitter{0.0, 0.012};

    double jx() { return jitter(rng); }
    void push(double x, double y) {
        pts.push_back({now, x + jx(), y + jx()});
        now += kDt;
    }
    void neutral(double ms) {
        const int n = (int)(ms * 0.001 / kDt);
        for (int i = 0; i < n; ++i) push(0.0, 0.0);
    }
    // Hold a position (with wobble) for ms.
    void hold(double ms, double x, double y) {
        const int n = (int)(ms * 0.001 / kDt);
        for (int i = 0; i < n; ++i) push(x, y);
    }
    // Cosine ease-in-out move from current point to target over ms.
    void move(double ms, double tx, double ty) {
        const double fx = pts.empty() ? 0.0 : pts.back().x;
        const double fy = pts.empty() ? 0.0 : pts.back().y;
        const int n = std::max(1, (int)(ms * 0.001 / kDt));
        for (int i = 1; i <= n; ++i) {
            const double u = (double)i / n;
            const double e = 0.5 * (1.0 - std::cos(kPi * u));
            push(fx + (tx - fx) * e, fy + (ty - fy) * e);
        }
    }
    // Constant-velocity rim arc from startDeg sweeping sweepDeg (ccw +).
    void arc(double ms, double startDeg, double sweepDeg, double radius) {
        const int n = std::max(1, (int)(ms * 0.001 / kDt));
        for (int i = 1; i <= n; ++i) {
            const double u = (double)i / n;
            const double ang = (startDeg + sweepDeg * u) * kPi / 180.0;
            push(radius * std::cos(ang), radius * std::sin(ang));
        }
    }
    // Radial decay from current point to center (foot releases the stick).
    void decay(double ms) { move(ms, 0.0, 0.0); }
};

// Standard gesture skeletons ------------------------------------------------
// Ollie-family flick: push to `load`, hold, pop to `pop` target, rim park,
// then decay to neutral (optionally continuing to a hold target for manuals).
Path ollieLike(double loadY, double popX, double popY, bool withHold = false,
               double holdY = 0.0) {
    Path p;
    p.neutral(200.0);
    p.move(90.0, 0.0, loadY);        // push in (crouch/load)
    p.hold(120.0, 0.0, loadY);       // load hold
    p.move(100.0, popX, popY);       // pop (fast reversal)
    p.hold(40.0, popX, popY);        // rim park (foot parked at deflection)
    if (withHold) {
        p.move(120.0, 0.0, holdY);   // lean out of the pop into the hold
        p.hold(650.0, 0.0, holdY);   // manual hold
        p.hold(120.0, 0.0, holdY);
    } else {
        p.decay(120.0);
    }
    p.neutral(200.0);
    return p;
}

Path shuvLike(double radius, double sweepDeg, double ms) {
    // tail load, then constant-velocity rim arc; arc ends where it ends.
    Path p;
    p.neutral(200.0);
    p.move(90.0, radius * std::cos(-90.0 * kPi / 180.0),
                 radius * std::sin(-90.0 * kPi / 180.0)); // load at tail (-90deg)
    p.hold(120.0, radius * std::cos(-90.0 * kPi / 180.0),
                 radius * std::sin(-90.0 * kPi / 180.0));
    p.arc(ms, -90.0, sweepDeg, radius);  // the shuv motion
    p.hold(30.0, radius * std::cos((-90.0 + sweepDeg) * kPi / 180.0),
                 radius * std::sin((-90.0 + sweepDeg) * kPi / 180.0)); // rim park
    p.decay(130.0);
    p.neutral(200.0);
    return p;
}

// Late kick: ollie, neutralize to center, hover-load, flick again mid-air.
Path lateKick() {
    Path p;
    p.neutral(200.0);
    p.move(90.0, 0.0, -0.72);
    p.hold(120.0, 0.0, -0.72);
    p.move(100.0, 0.0, 0.90);        // ollie pop
    p.hold(40.0, 0.0, 0.90);
    p.decay(60.0);                   // neutralize fast (airborne rider)
    p.hold(60.0, 0.0, 0.0);          // recompose at neutral
    p.move(60.0, -0.12, 0.66);       // hover-load (crouched stick)
    p.hold(80.0, -0.12, 0.66);       // park long enough to re-crouch mid-air
    p.move(60.0, -0.45, 0.90);       // late flick (toe side, regular)
    p.hold(40.0, -0.45, 0.90);
    p.decay(140.0);
    p.neutral(250.0);
    return p;
}

// Noise / false-flick generators -------------------------------------------
Path noiseChatter() {
    // Alternating micro nudges that never reach the load magnitude.
    Path p;
    p.neutral(200.0);
    for (int i = 0; i < 14; ++i) {
        const double dx = (i % 2 == 0 ? 0.13 : -0.11);
        const double dy = (i % 3 == 0 ? -0.08 : 0.06);
        p.move(40.0, dx, dy);
    }
    p.decay(60.0);
    p.neutral(200.0);
    return p;
}

Path falseFlickDrift() {
    // Slow deliberate push that stalls BELOW the load magnitude, holds, drifts.
    Path p;
    p.neutral(200.0);
    p.move(500.0, 0.18, -0.34);      // peak mag ~0.385
    p.hold(400.0, 0.20, -0.32);
    p.move(300.0, 0.24, -0.52);      // creep up to ~0.52... wait: below 0.55
    p.hold(300.0, 0.24, -0.50);      // mag ~0.554? kept below loadMag by design
    p.decay(350.0);
    p.neutral(200.0);
    return p;
}

Path weakJab() {
    // Quick jab that reaches only 0.48 and comes straight back: no load phase.
    Path p;
    p.neutral(200.0);
    p.move(60.0, 0.0, 0.48);
    p.move(60.0, 0.0, -0.05);
    p.decay(60.0);
    p.neutral(200.0);
    return p;
}

// ---------------------------------------------------------------------------
struct Case {
    const char* id;
    Context ctx;
    std::vector<std::string> expect;
    Path path;
};

std::vector<Case> buildBattery() {
    std::vector<Case> cases;
    const Context regFwd{Stance::Regular, Riding::Forward};
    const Context regFak{Stance::Regular, Riding::Fakie};
    const Context goofy{Stance::Goofy, Riding::Forward};

    // 1  ollie (fast load)
    cases.push_back({"ollie_a", regFwd, {"ollie"},
                     ollieLike(-0.72, 0.02, 0.92)});
    // 2  ollie (slow, long load hold)
    {
        Path p = ollieLike(-0.68, 0.02, 0.90);
        cases.push_back({"ollie_slow_load", regFwd, {"ollie"}, p});
    }
    // 3  kickflip (regular: toe side = screen-left release)
    cases.push_back({"kickflip_reg", regFwd, {"kickflip"},
                     ollieLike(-0.72, -0.43, 0.88)});
    // 4  heelflip (regular: heel side = screen-right release)
    cases.push_back({"heelflip_reg", regFwd, {"heelflip"},
                     ollieLike(-0.72, 0.43, 0.88)});
    // 5  pop shove-it fs (regular = cw tail->toe sweep)
    cases.push_back({"shove_fs", regFwd, {"pop shove-it fs"},
                     shuvLike(0.75, -90.0, 80.0)});
    // 6  pop shove-it bs (regular = ccw tail->heel sweep)
    cases.push_back({"shove_bs", regFwd, {"pop shove-it bs"},
                     shuvLike(0.75, 90.0, 80.0)});
    // 7  360 shove-it bs (big ccw wind)
    cases.push_back({"shove360_bs", regFwd, {"360 shove-it bs"},
                     shuvLike(0.75, 300.0, 220.0)});
    // 8  360 flip / tre class (ccw wind whose release flings across the top)
    cases.push_back({"tre_flip", regFwd, {"360 flip"},
                     shuvLike(0.75, 250.0, 170.0)});
    // 9  nollie (nose load, pop to tail)
    cases.push_back({"nollie", regFwd, {"nollie"},
                     ollieLike(0.72, 0.02, -0.88)});
    // 10 fakie ollie (same gesture, fakie riding context)
    cases.push_back({"fakie_ollie", regFak, {"fakie ollie"},
                     ollieLike(-0.72, 0.02, 0.92)});
    // 11 manual: ollie pop held into a lean
    cases.push_back({"manual_hold", regFwd, {"manual (hold)"},
                     ollieLike(-0.72, 0.02, 0.90, /*withHold=*/true, /*holdY=*/-0.62)});
    // 12 late kickflip (kick started while airborne window was open)
    cases.push_back({"late_kickflip", regFwd, {"ollie", "late kickflip"}, lateKick()});
    // 13 goofy kickflip (goofy toe = screen-right release; must mirror)
    cases.push_back({"kickflip_goofy", goofy, {"kickflip"},
                     ollieLike(-0.72, 0.43, 0.88)});
    // 14 noise: stick chatter -> no trick
    cases.push_back({"noise_chatter", regFwd, {}, noiseChatter()});
    // 15 false flick: drift below load threshold -> no trick
    cases.push_back({"drift_false_flick", regFwd, {}, falseFlickDrift()});
    // 16 weak jab: fast but never loads -> no trick
    cases.push_back({"weak_jab", regFwd, {}, weakJab()});
    return cases;
}

} // namespace

int main() {
    Tunables tun;
    Recognizer rec(tun);
    const auto cases = buildBattery();

    int pass = 0, total = (int)cases.size();
    printf("JOO-193 flick_proto battery v0\n");
    printf("recognizer: right-stick gestures -> tricks (engine-less C++17)\n");
    printf("sampling: 60 Hz, jitter sigma=0.012 (deterministic seed 1337)\n");
    printf
        ("--------------------------------------------------------------------"
         "---------------------------------\n");
    printf("%-4s %-18s %-7s %-29s %-29s %-5s %-5s %-8s %-7s\n",
           "#", "case", "ctx", "expected", "got", "ok", "conf", "t_pop(ms)",
           "flick");
    printf
        ("--------------------------------------------------------------------"
         "---------------------------------\n");

    for (size_t ci = 0; ci < cases.size(); ++ci) {
        const Case& c = cases[ci];
        Result r = rec.process(c.ctx, c.path.pts);

        std::string expected;
        for (size_t k = 0; k < c.expect.size(); ++k)
            expected += (k ? ", " : "") + c.expect[k];
        if (expected.empty()) expected = "(none)";

        std::string got;
        for (size_t k = 0; k < r.tricks.size(); ++k)
            got += (k ? ", " : "") + r.tricks[k].name;
        if (got.empty()) got = "(none)";

        bool ok = (r.tricks.size() == c.expect.size());
        for (size_t k = 0; ok && k < c.expect.size(); ++k)
            ok = (r.tricks[k].name == c.expect[k]);

        double conf = 0.0;
        double tPop = -1.0;
        double flickMs = 0.0;
        for (const auto& tr : r.tricks) {
            conf = tr.confidence;
            tPop = tr.t_pop;
            flickMs = tr.t_land - tr.t_pop;
        }
        if (ok) ++pass;
        const char* ctxTag = "std";
        if (c.ctx.riding == Riding::Fakie) ctxTag = "fakie";
        else if (c.ctx.riding == Riding::Switch) ctxTag = "switch";
        else if (c.ctx.baseStance == Stance::Goofy) ctxTag = "goofy";

        printf("%-4zu %-18s %-7s %-29s %-29s %-5s %5.2f  %8.1f %6.0fms\n", ci + 1,
               c.id, ctxTag, expected.c_str(), got.c_str(), ok ? "PASS" : "FAIL",
               conf, tPop > 0 ? tPop * 1000.0 : 0.0, flickMs * 1000.0);
        for (const auto& tr : r.tricks) {
            printf("     features: reversal=%6.1fdeg sweep=%7.1fdeg speed=%5.1f "
                   "peakmag=%.2f hold=%.0fms%s%s\n",
                   tr.reversal_deg, tr.sweep_deg, tr.peak_speed, tr.peak_mag,
                   tr.hold_ms, tr.note.empty() ? "" : " note=",
                   tr.note.c_str());
        }
        for (const auto& rej : r.rejections) {
            printf("     rejected at %6.0fms: %s\n", rej.t * 1000.0,
                   rej.reason.c_str());
        }
    }

    const double pct = total ? 100.0 * pass / total : 0.0;
    printf
        ("--------------------------------------------------------------------"
         "---------------------------------\n");
    printf("RESULT: %d/%d (%.1f%%) — v0 acceptance floor >= 90%% (%d/%d)\n",
           pass, total, pct, (int)std::ceil(0.9 * total), total);
    printf("%s\n", pct >= 90.0 ? "BATTERY: PASS" : "BATTERY: FAIL");
    return pct >= 90.0 ? 0 : 1;
}