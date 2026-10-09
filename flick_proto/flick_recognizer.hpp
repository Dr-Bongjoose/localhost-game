// flick_recognizer.hpp
// LOCALHOST flick_proto — right-stick gesture recognition, engine-less C++17.
//
// Clean-room statement: this file is original code, written from the project's
// own model of stick gestures and common skateboarding terminology (publicly
// observable physical behavior + standard trick names). No third-party code,
// assets, symbols, or names are referenced or derived.
//
// Model (see README.md for the full walkthrough):
//   Input  : stream of right-stick samples {t, x, y}, x/y in [-1, 1]
//   Phases : idle -> load -> flick -> recover (+ optional hold)
//   Context: stance (regular/goofy), riding (forward/fakie/switch)
//   Output : list of recognized TrickEvent (name, timing, confidence)

#pragma once
#include <string>
#include <vector>

namespace flick {

// One right-stick sample at time t (seconds). x/y in [-1, 1].
// Screen convention (camera behind rider, rider travels up-screen):
//   +y = travel direction (nose side)      -y = tail side
//   x  = screen sides, stance-relative (see README "Coordinate convention")
struct Sample {
    double t = 0.0;
    double x = 0.0;
    double y = 0.0;
};

enum class Stance { Regular, Goofy };
enum class Riding { Forward, Fakie, Switch };

// Riding context the game already knows (motion state), NOT part of gesture.
struct Context {
    Stance baseStance = Stance::Regular;
    Riding riding = Riding::Forward;
};

// All thresholds live here so battery runs / future calibration can sweep them.
// v0 values were derived from scripted gesture kinematics (see README); the
// follow-up step is re-deriving them from real controller captures.
struct Tunables {
    double idleMag          = 0.30;  // below: stick reads as neutral
    double loadMag          = 0.55;  // sustained reach of this => LOAD (crouch)
    double loadSustainMs    = 36.0;  // mag >= loadMag held this long => LOAD
    double flickSpeed       = 6.0;   // stick speed (units/s) => flick motion
    double flickAfterLoadMs = 150.0; // pop must begin within this after LOAD
    double minMagForArc     = 0.45;  // arc accumulation gate (both samples)
    double flickCapMs       = 500.0; // safety cap on one flick phase
    double loadStillSpeed   = 2.0;   // load must complete below this speed

    double microArcDeg      = 20.0;  // flick with arc below AND dur below = noise
    double microFlickMs     = 45.0;

    double flipPopX         = 0.22;  // |release.x| >=: flip component present
    double flipPopY         = 0.12;  // release must also point up-ish to flip
    double bigArcDeg        = 230.0; // arc >=: 360-family (shove / 360 flip)
    double treReleaseY      = 0.15;  // 360-family: release tilts up => 360 flip

    double popShoveArcDeg   = 90.0;  // ideal arc (confidence target)
    double bigArcTargetDeg  = 300.0; // ideal arc for 360 shove naming
    double treArcTargetDeg  = 250.0; // ideal arc for 360 flip naming

    double holdMag          = 0.45;  // post-flick lean >=: hold (manual family)
    double holdMs           = 250.0; // sustained lean => hold complete
    double holdConeDeg      = 75.0;  // direction tolerance around tail / nose
    double holdWatchMs      = 900.0; // how long after flick a hold may still land

    double lateWindowMs     = 300.0; // flick inside window of previous => "late"
};

// A motion the stick made that was inspected and NOT promoted to a trick.
struct Rejection {
    double t = 0.0;
    std::string reason;
};

struct TrickEvent {
    std::string name;        // "ollie", "fakie ollie", "kickflip",
                             // "pop shove-it fs"/"bs", "360 shove-it fs"/"bs",
                             // "360 flip", "late kickflip", "manual (hold)"...
    double t_pop = 0.0;      // flick start (s, stream clock)
    double t_land = 0.0;     // flick end / hold end (s)
    double air_ms = 0.0;     // pop->land window; for "late": since previous pop
    double confidence = 0.0; // 0..1, how solidly the pattern matched
    // Feature trace (for evidence + tuning):
    double reversal_deg = 0.0;   // angle between load direction and release
    double sweep_deg = 0.0;      // signed arc swept during flick (ccw positive)
    double peak_speed = 0.0;     // stick units/s
    double peak_mag = 0.0;       // stick magnitude at peak
    double hold_ms = 0.0;        // >0 when a hold completed
    std::string note;            // context-decoration trace
};

struct Result {
    std::vector<TrickEvent> tricks;
    std::vector<Rejection> rejections;
};

// Offline recognizer: processes one whole sample stream per call. A real
// engine feeds samples incrementally; the state machine below is written so a
// future incremental wrapper can reuse it (documented in README).
class Recognizer {
public:
    explicit Recognizer(const Tunables& t = Tunables{}) : t_(t) {}
    Result process(const Context& ctx, const std::vector<Sample>& stream) const;

private:
    Tunables t_;
};

} // namespace flick