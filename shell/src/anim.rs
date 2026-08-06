//! Motion engine — eased value animation for the owned chrome.
//!
//! QML parity timings (COMPOSITOR/CHROME reference): dock magnify 70ms,
//! hover/status color 140ms, HUD fade 160ms, workspace pill 180ms, CC open
//! 200ms, auto-hide slide 220ms — all OutCubic; notif dismiss 140ms InCubic.
//! A ~60fps tick subscription runs only while something is animating.

use std::time::{Duration, Instant};

/// Easing curves used by the QML chrome.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Easing {
    Linear,
    OutCubic,
    InCubic,
    OutQuad,
    InQuad,
}

impl Easing {
    /// Map linear progress `t` in `[0, 1]` through the curve.
    pub fn apply(self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);
        match self {
            Easing::Linear => t,
            Easing::OutCubic => 1.0 - (1.0 - t).powi(3),
            Easing::InCubic => t.powi(3),
            Easing::OutQuad => 1.0 - (1.0 - t) * (1.0 - t),
            Easing::InQuad => t * t,
        }
    }
}

/// One in-flight tween between two values.
#[derive(Debug, Clone, Copy)]
struct Tween {
    from: f32,
    to: f32,
    start: Instant,
    dur: Duration,
    easing: Easing,
}

impl Tween {
    fn value(&self, now: Instant) -> f32 {
        if self.dur.is_zero() {
            return self.to;
        }
        let t = now.saturating_duration_since(self.start).as_secs_f32() / self.dur.as_secs_f32();
        self.from + (self.to - self.from) * self.easing.apply(t)
    }

    fn done(&self, now: Instant) -> bool {
        now.saturating_duration_since(self.start) >= self.dur
    }
}

/// A persistent animated scalar — retarget any time, read every frame.
#[derive(Debug, Clone, Copy)]
pub struct AnimatedValue {
    target: f32,
    tween: Option<Tween>,
}

impl AnimatedValue {
    pub fn new(value: f32) -> Self {
        Self {
            target: value,
            tween: None,
        }
    }

    /// Jump without animation.
    pub fn set(&mut self, value: f32) {
        self.target = value;
        self.tween = None;
    }

    /// Ease from the current (possibly mid-flight) value to a new target.
    pub fn animate_to(&mut self, to: f32, dur_ms: u64, easing: Easing) {
        let now = Instant::now();
        if (self.target - to).abs() < f32::EPSILON && self.tween.is_none() {
            return;
        }
        let from = self.value_at(now);
        self.target = to;
        self.tween = Some(Tween {
            from,
            to,
            start: now,
            dur: Duration::from_millis(dur_ms),
            easing,
        });
    }

    /// Current value at `now` (settles to the target when done).
    pub fn value_at(&self, now: Instant) -> f32 {
        match &self.tween {
            Some(tw) if !tw.done(now) => tw.value(now),
            _ => self.target,
        }
    }

    /// Convenience: value at `Instant::now()`.
    pub fn value(&self) -> f32 {
        self.value_at(Instant::now())
    }

    /// Final target regardless of tween state.
    pub fn target(&self) -> f32 {
        self.target
    }

    /// Whether a tween is still in flight at `now`.
    pub fn animating_at(&self, now: Instant) -> bool {
        matches!(&self.tween, Some(tw) if !tw.done(now))
    }

    pub fn animating(&self) -> bool {
        self.animating_at(Instant::now())
    }
}

impl Default for AnimatedValue {
    fn default() -> Self {
        Self::new(0.0)
    }
}

/// Linear keyframe sequence (lock shake: −12 → 12 → −8 → 0 over 40/50/40/40ms).
#[derive(Debug, Clone)]
pub struct Keyframes {
    start: Instant,
    /// (offset from start, value) pairs — first frame is the initial value.
    frames: Vec<(Duration, f32)>,
}

impl Keyframes {
    /// Build from `(duration_ms, value)` segments starting at `initial`.
    pub fn new(initial: f32, segments: &[(u64, f32)]) -> Self {
        let mut frames = vec![(Duration::ZERO, initial)];
        let mut at = Duration::ZERO;
        for (ms, v) in segments {
            at += Duration::from_millis(*ms);
            frames.push((at, *v));
        }
        Self {
            start: Instant::now(),
            frames,
        }
    }

    /// The QML lock failure shake.
    pub fn shake() -> Self {
        Self::new(0.0, &[(40, -12.0), (50, 12.0), (40, -8.0), (40, 0.0)])
    }

    pub fn value_at(&self, now: Instant) -> f32 {
        let elapsed = now.saturating_duration_since(self.start);
        let mut prev = self.frames[0];
        for frame in &self.frames[1..] {
            if elapsed < frame.0 {
                let span = (frame.0 - prev.0).as_secs_f32();
                if span <= f32::EPSILON {
                    return frame.1;
                }
                let t = (elapsed - prev.0).as_secs_f32() / span;
                return prev.1 + (frame.1 - prev.1) * t;
            }
            prev = *frame;
        }
        prev.1
    }

    pub fn value(&self) -> f32 {
        self.value_at(Instant::now())
    }

    pub fn done_at(&self, now: Instant) -> bool {
        match self.frames.last() {
            Some((end, _)) => now.saturating_duration_since(self.start) >= *end,
            None => true,
        }
    }

    pub fn done(&self) -> bool {
        self.done_at(Instant::now())
    }
}

/// One-shot deadline (HUD 1500ms / toast 4500ms auto-hide).
#[derive(Debug, Clone, Copy)]
pub struct Deadline {
    at: Instant,
}

impl Deadline {
    pub fn after_ms(ms: u64) -> Self {
        Self {
            at: Instant::now() + Duration::from_millis(ms),
        }
    }

    pub fn expired_at(&self, now: Instant) -> bool {
        now >= self.at
    }

    pub fn expired(&self) -> bool {
        self.expired_at(Instant::now())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn easing_endpoints_are_exact() {
        for e in [
            Easing::Linear,
            Easing::OutCubic,
            Easing::InCubic,
            Easing::OutQuad,
            Easing::InQuad,
        ] {
            assert!((e.apply(0.0) - 0.0).abs() < 1e-6);
            assert!((e.apply(1.0) - 1.0).abs() < 1e-6);
        }
        // OutCubic front-loads motion; InCubic back-loads it.
        assert!(Easing::OutCubic.apply(0.5) > 0.5);
        assert!(Easing::InCubic.apply(0.5) < 0.5);
    }

    #[test]
    fn animated_value_settles_on_target() {
        let mut v = AnimatedValue::new(0.0);
        v.animate_to(1.0, 50, Easing::OutCubic);
        assert!(v.animating());
        let mid = v.value();
        assert!((0.0..=1.0).contains(&mid));
        let end = Instant::now() + Duration::from_millis(80);
        assert!((v.value_at(end) - 1.0).abs() < 1e-6);
        assert!(!v.animating_at(end));
    }

    #[test]
    fn animated_value_retargets_from_midflight() {
        let mut v = AnimatedValue::new(0.0);
        v.animate_to(1.0, 1000, Easing::Linear);
        std::thread::sleep(Duration::from_millis(20));
        v.animate_to(0.0, 100, Easing::Linear);
        // New tween starts from the mid-flight value, not from 1.0.
        assert!(v.value() < 0.6);
        assert_eq!(v.target(), 0.0);
    }

    #[test]
    fn keyframes_shake_returns_to_zero() {
        let shake = Keyframes::shake();
        let end = Instant::now() + Duration::from_millis(200);
        assert!((shake.value_at(end)).abs() < 1e-6);
        assert!(shake.done_at(end));
    }

    #[test]
    fn deadline_expires() {
        let d = Deadline::after_ms(10);
        assert!(!d.expired());
        assert!(d.expired_at(Instant::now() + Duration::from_millis(20)));
    }
}
