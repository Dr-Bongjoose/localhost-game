// flick_recognizer.cpp
// LOCALHOST flick_proto — implementation of the stick-gesture recognizer.
// Original clean-room code; see flick_recognizer.hpp for the model.

#include "flick_recognizer.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

namespace flick {
namespace {

constexpr double kPi = 3.14159265358979323846;

double degOf(double rad) { return rad * 180.0 / kPi; }
double magOf(const Sample& s) { return std::hypot(s.x, s.y); }
double angleOf(const Sample& s) { return degOf(std::atan2(s.y, s.x)); }
double clamp01(double v) { return std::clamp(v, 0.0, 1.0); }

// Wrap any angle difference into [-180, 180).
double wrap180(double d) {
    while (d >= 180.0) d -= 360.0;
    while (d < -180.0) d += 360.0;
    return d;
}

// Spins: REGULAR backside = tail sweeps toward heel (= +x) = ccw (+) sweep.
// GOOFY mirrors; SWITCH inverts again. (Convention documented in README.)
bool isBackside(double signedSweepDeg, Stance base, Riding riding) {
    bool reg = base == Stance::Regular;
    if (riding == Riding::Switch) reg = !reg;
    return reg ? signedSweepDeg > 0.0 : signedSweepDeg < 0.0;
}

enum class Fam { Unknown, Ollie, Nollie, Kick, Heel, PopShove, SpinShove, SpinFlip };

struct Verdict {
    Fam fam = Fam::Unknown;
    std::string name;       // base trick name (before riding decoration)
    double confidence = 0.0;
};

struct Flick {
    double t_start = 0.0;
    double t_end = 0.0;
    double load_x = 0.0, load_y = 0.0;       // averaged load direction (unit)
    bool load_nose = false;                  // load leaned toward nose (+y)
    double release_x = 0.0, release_y = 0.0; // unit direction at last kept sample
    double reversal_deg = 0.0;               // angle(load, release), filled at end
    double sweep_deg = 0.0;                  // signed arc (ccw +)
    double peak_speed = 0.0;                 // stick units/s
    double peak_mag = 0.0;
};

// Classification order matters (README decision tree):
//   1. 360-family (big arcs)  2. flips (toe/heel release)  3. shove arcs
//   4. ollie/nollie (straight reversal, named by load side)  5. unknown
Verdict classify(const Flick& f, const Context& ctx, const Tunables& t) {
    Verdict v;
    const double arc = std::fabs(f.sweep_deg);
    const double speedC = clamp01((f.peak_speed - 6.0) / 12.0);

    // 1) 360 family
    if (arc >= t.bigArcDeg) {
        if (f.release_y >= t.treReleaseY) {
            v.fam = Fam::SpinFlip;
            v.name = "360 flip";
            const double arcC = clamp01(1.0 - std::fabs(arc - t.treArcTargetDeg) / 150.0);
            v.confidence = 0.45 * speedC + 0.55 * arcC;
            return v;
        }
        v.fam = Fam::SpinShove;
        v.name = std::string("360 shove-it ") +
                 (isBackside(f.sweep_deg, ctx.baseStance, ctx.riding) ? "bs" : "fs");
        const double arcC = clamp01(1.0 - std::fabs(arc - t.bigArcTargetDeg) / 150.0);
        v.confidence = 0.45 * speedC + 0.55 * arcC;
        return v;
    }

    // 2) flips — release tilted off-straight toward one stick side, up-ish
    if (std::fabs(f.release_x) >= t.flipPopX && f.release_y >= t.flipPopY) {
        const double sideRel =
            f.release_x * (ctx.baseStance == Stance::Regular ? 1.0 : -1.0);
        v.fam = (sideRel <= -t.flipPopX) ? Fam::Kick : Fam::Heel;
        v.name = (v.fam == Fam::Kick) ? "kickflip" : "heelflip";
        const double straightC =
            clamp01(1.0 - std::fabs(std::fabs(f.release_x) - 0.42) / 0.35);
        v.confidence = 0.55 * straightC + 0.45 * speedC;
        return v;
    }

    // 3) pop shove-it family — arc in the 55..bigArc band, release not flipping
    if (arc >= 55.0) {
        v.fam = Fam::PopShove;
        v.name = std::string("pop shove-it ") +
                 (isBackside(f.sweep_deg, ctx.baseStance, ctx.riding) ? "bs" : "fs");
        const double arcC = clamp01(1.0 - std::fabs(arc - t.popShoveArcDeg) / 110.0);
        v.confidence = 0.55 * arcC + 0.45 * speedC;
        return v;
    }

    // 4) ollie / nollie — clean reversal, small arc; load side names the family
    if (f.reversal_deg >= 140.0 && std::fabs(f.release_x) < t.flipPopX) {
        const bool upPop = f.release_y >= 0.5;
        const bool downPop = f.release_y <= -0.5;
        if (f.load_nose ? downPop : upPop) {
            v.fam = f.load_nose ? Fam::Nollie : Fam::Ollie;
            v.name = f.load_nose ? "nollie" : "ollie";
            const double revC = clamp01(1.0 - std::fabs(f.reversal_deg - 180.0) / 70.0);
            const double straightC = clamp01(1.0 - std::fabs(f.release_y) / 1.2);
            v.confidence = 0.4 * speedC + 0.35 * revC + 0.25 * straightC;
            return v;
        }
    }

    v.fam = Fam::Unknown;
    v.name = "unknown flick";
    v.confidence = 0.15;
    return v;
}

} // namespace

Result Recognizer::process(const Context& ctx, const std::vector<Sample>& stream) const {
    Result out;
    const Tunables& t = t_;
    if (stream.size() < 2) return out;

    // Light exponential smoothing (kills sensor noise, keeps flick shape).
    std::vector<Sample> sm;
    sm.reserve(stream.size());
    const double smooth = 0.45;
    double sx = stream.front().x, sy = stream.front().y;
    for (const auto& s : stream) {
        sx += smooth * (s.x - sx);
        sy += smooth * (s.y - sy);
        sm.push_back({s.t, sx, sy});
    }

    bool inFlick = false;
    Flick f{};
    double prevAngle = angleOf(sm.front());

    // Load tracking. Entry needs loadMag; the crouch then holds down to
    // loadMag - 0.25 (hysteresis band ≈ idle) so the pop's smoothing lag
    // cannot drop the load before the trigger sample arrives.
    const double loadKeep = t.loadMag - 0.25;
    bool loadSatisfied = false;
    bool loadNearStill = false;
    double loadMagHoldStart = -1.0;
    double loadSustainedAt = 0.0;
    double loadSumX = 0.0, loadSumY = 0.0;
    int loadN = 0;
    auto resetLoad = [&]() {
        loadSatisfied = false;
        loadNearStill = false;
        loadMagHoldStart = -1.0;
        loadSumX = 0.0;
        loadSumY = 0.0;
        loadN = 0;
    };

    // A new pop may only begin after the stick read as idle since the last
    // flick ended. This keeps a pop->hold lean (manual descent) from firing
    // as a phantom second trick; chaining real tricks passes through neutral.
    bool idleSinceLastFlick = true;

    // Hold watch (manual family) after a flick ends.
    bool holdWatch = false;
    bool holdResolved = false;
    double holdWatchStart = 0.0;
    bool holdClockRunning = false;
    double holdClockStart = 0.0;
    int holdSide = 0; // -1 tail, +1 nose

    TrickEvent lastEvent;
    bool haveLast = false;

    auto emitTrick = [&](const Flick& fl) {
        Verdict v = classify(fl, ctx, t);
        std::string name = v.name;
        std::string note;
        if (ctx.riding == Riding::Switch) {
            note = "riding=switch (naming stance note pending v1)";
        }
        if (ctx.riding == Riding::Fakie) {
            name = "fakie " + name;
            note = note.empty() ? "riding=fakie" : note + "; riding=fakie";
        }
        const bool late = haveLast && (fl.t_start - lastEvent.t_pop) >= 0.0 &&
                          (fl.t_start - lastEvent.t_land) * 1000.0 <= t.lateWindowMs;
        if (late) {
            name = "late " + name;
            note = note.empty() ? "inside airborne window" : note + "; inside airborne window";
        }

        TrickEvent ev;
        ev.name = name;
        ev.note = note;
        ev.t_pop = fl.t_start;
        ev.t_land = fl.t_end;
        ev.air_ms = late ? (haveLast ? (fl.t_start - lastEvent.t_pop) * 1000.0 : 0.0)
                         : (fl.t_end - fl.t_start) * 1000.0;
        ev.confidence = clamp01(v.confidence);
        ev.reversal_deg = fl.reversal_deg;
        ev.sweep_deg = fl.sweep_deg;
        ev.peak_speed = fl.peak_speed;
        ev.peak_mag = fl.peak_mag;
        out.tricks.push_back(ev);
        lastEvent = ev;
        haveLast = true;
    };

    for (size_t i = 1; i < sm.size(); ++i) {
        const Sample& cur = sm[i];
        const Sample& prev = sm[i - 1];
        const double dt = cur.t - prev.t;
        const double curMag = magOf(cur);
        const double curAngle = angleOf(cur);
        double moveSpeed = 0.0;
        if (dt > 0.0) moveSpeed = std::hypot(cur.x - prev.x, cur.y - prev.y) / dt;

        if (curMag < t.idleMag) idleSinceLastFlick = true;

        // ---- hold watch: lean after a flick may resolve into manual family
        if (holdWatch) {
            const bool tailIn = std::fabs(wrap180(curAngle + 90.0)) <= t.holdConeDeg;
            const bool noseIn = std::fabs(wrap180(curAngle - 90.0)) <= t.holdConeDeg;
            if (curMag >= t.holdMag && (tailIn || noseIn)) {
                const int side = noseIn ? +1 : -1;
                if (!holdClockRunning || holdSide != side) {
                    holdClockRunning = true;
                    holdSide = side;
                    holdClockStart = cur.t;
                }
                const double heldMs = (cur.t - holdClockStart) * 1000.0;
                if ((cur.t - holdWatchStart) * 1000.0 > t.holdWatchMs) {
                    holdWatch = false;
                } else if (heldMs >= t.holdMs && !out.tricks.empty() && !holdResolved) {
                    TrickEvent& last = out.tricks.back();
                    const bool ollieFam = last.name.find("ollie") != std::string::npos ||
                                          last.name.find("nollie") != std::string::npos;
                    if (ollieFam) {
                        const std::string fakie =
                            last.name.rfind("fakie ", 0) == 0 ? "fakie " : "";
                        last.name = fakie + (holdSide < 0 ? "manual (hold)"
                                                          : "nose manual (hold)");
                        last.t_land = cur.t;
                        last.hold_ms = heldMs;
                        const double revC =
                            clamp01(1.0 - std::fabs(last.reversal_deg - 180.0) / 70.0);
                        const double holdC = clamp01(heldMs / 450.0);
                        last.confidence = clamp01(0.35 * revC + 0.65 * holdC);
                        last.note += last.note.empty() ? "pop held into hold"
                                                       : "; pop held into hold";
                    } else {
                        last.note += last.note.empty()
                                         ? "hold after trick (not manual-eligible)"
                                         : "; hold after trick";
                    }
                    holdResolved = true;
                    holdWatch = false;
                    holdClockRunning = false;
                }
            } else {
                holdClockRunning = false;
            }
        }

        // ---- flick burst bookkeeping
        if (inFlick) {
            f.peak_speed = std::max(f.peak_speed, moveSpeed);
            f.peak_mag = std::max(f.peak_mag, curMag);
            if (curMag >= 0.35) {
                f.release_x = cur.x / curMag;
                f.release_y = cur.y / curMag;
            }
            // Arc accumulates only across CONSECUTIVE kept samples: when the
            // stick passes near center the angular delta is undefined, so the
            // gap is skipped instead of wrapped.
            if (magOf(prev) >= t.minMagForArc && curMag >= t.minMagForArc) {
                f.sweep_deg += wrap180(curAngle - prevAngle);
            }

            // A burst is one fast motion: it ends at the first slow sample
            // (foot parked at the rim / apex) or at the 500 ms cap. NO
            // magnitude cut: a real pop passes near center while still fast,
            // and cutting there truncates ollies into "unknown flick"s.
            if (moveSpeed < t.flickSpeed) {
                if ((cur.t - f.t_start) * 1000.0 >= 16.0) {
                    f.t_end = cur.t;
                    inFlick = false;
                    idleSinceLastFlick = false;
                    const double durMs = (f.t_end - f.t_start) * 1000.0;
                    const bool micro =
                        durMs < t.microFlickMs && std::fabs(f.sweep_deg) < t.microArcDeg;
                    if (!micro) {
                        f.reversal_deg =
                            degOf(std::acos(std::clamp(
                                f.load_x * f.release_x + f.load_y * f.release_y,
                                -1.0, 1.0)));
                        emitTrick(f);
                    } else {
                        out.rejections.push_back({f.t_start, "micro-flick (noise)"});
                    }
                    if (!micro) {
                        holdWatch = true;
                        holdWatchStart = f.t_end;
                        holdClockRunning = false;
                        holdResolved = false;
                    }
                }
            } else if ((cur.t - f.t_start) * 1000.0 > t.flickCapMs) {
                f.t_end = cur.t;
                inFlick = false;
                idleSinceLastFlick = false;
                out.rejections.push_back({f.t_start, "flick cap exceeded"});
                holdWatch = false;
            }
        }

        // ---- idle / load / pop trigger
        if (!inFlick) {
            const double maintainGate = loadSatisfied ? loadKeep : t.loadMag;
            if (curMag >= maintainGate) {
                if (loadMagHoldStart < 0.0) loadMagHoldStart = cur.t;
                if (!loadSatisfied &&
                    (cur.t - loadMagHoldStart) * 1000.0 >= t.loadSustainMs) {
                    loadSatisfied = true;
                    loadSustainedAt = cur.t;
                    // A pop only comes off a PARKED crouch: the load must
                    // complete while the stick is near-still. Sustain that
                    // completes mid-motion is the same gesture continuing
                    // (e.g. pop->manual lean), not a new crouch.
                    loadNearStill = moveSpeed < t.loadStillSpeed;
                    loadSumX = 0.0;
                    loadSumY = 0.0;
                    loadN = 0;
                }
                if (loadSatisfied) {
                    loadSumX += cur.x;
                    loadSumY += cur.y;
                    ++loadN;
                }
            } else if (loadSatisfied && curMag < t.idleMag) {
                // Post-trick decay passes through the load band while the
                // stick resets; only record releases when the crouch was NOT
                // continuation residue of a trick that landed recently.
                const bool postTrickResidue =
                    haveLast && loadSustainedAt < lastEvent.t_land + 0.6;
                if (!postTrickResidue && out.rejections.size() < 30)
                    out.rejections.push_back({loadSustainedAt, "load released, no flick"});
                resetLoad();
            } else if (curMag < maintainGate) {
                if (loadSatisfied && curMag < t.loadMag && moveSpeed < t.flickSpeed) {
                    // dipped out of the maintain band without a pop
                    if (out.rejections.size() < 30) {
                        out.rejections.push_back({loadSustainedAt, "load dropped, no flick"});
                    }
                }
                resetLoad();
            }

            if (loadSatisfied && loadNearStill && idleSinceLastFlick &&
                moveSpeed >= t.flickSpeed &&
                (cur.t - loadSustainedAt) * 1000.0 <= t.flickAfterLoadMs) {
                // -> FLICK burst starts
                inFlick = true;
                f = Flick{};
                f.t_start = prev.t;
                f.load_x = loadSumX / std::max(1, loadN);
                f.load_y = loadSumY / std::max(1, loadN);
                const double lmag = std::hypot(f.load_x, f.load_y);
                if (lmag > 1e-6) { f.load_x /= lmag; f.load_y /= lmag; }
                f.load_nose = f.load_y > 0.0;
                f.release_x = curMag > 0 ? cur.x / curMag : 0.0;
                f.release_y = curMag > 0 ? cur.y / curMag : 0.0;
                f.sweep_deg = 0.0;
                if (magOf(prev) >= t.minMagForArc && curMag >= t.minMagForArc)
                    f.sweep_deg = wrap180(curAngle - angleOf(prev));
                f.peak_speed = moveSpeed;
                f.peak_mag = curMag;
                resetLoad();
                holdWatch = false;
            }
        }

        prevAngle = curAngle;
    }

    return out;
}

} // namespace flick