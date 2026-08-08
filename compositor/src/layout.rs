//! Tiling math (OWNED-STACK compositor spike).
//! Pure geometry — compositor applies via Space + configure.
//! Layouts: equal-column, dwindle (default), master+stack.
//! Gaps: outer inset on work area + uniform inner inset per tile.

use smithay::utils::{Logical, Rectangle};

/// Global work area from output geometry + layer-map local non-exclusive zone.
/// `non_exclusive_local` is relative to the output origin (smithay LayerMap).
pub fn work_area_with_exclusive(
    output_geo: Rectangle<i32, Logical>,
    non_exclusive_local: Rectangle<i32, Logical>,
) -> Rectangle<i32, Logical> {
    let loc = (
        output_geo.loc.x + non_exclusive_local.loc.x,
        output_geo.loc.y + non_exclusive_local.loc.y,
    );
    let size = (
        non_exclusive_local.size.w.max(0),
        non_exclusive_local.size.h.max(0),
    );
    Rectangle::new(loc.into(), size.into())
}

/// Shrink `r` by `gap` on all sides (size clamped to ≥ 1 when originally positive).
pub fn inset_rect(r: Rectangle<i32, Logical>, gap: i32) -> Rectangle<i32, Logical> {
    if gap <= 0 {
        return r;
    }
    if r.size.w <= 0 || r.size.h <= 0 {
        return r;
    }
    let w = (r.size.w - 2 * gap).max(1);
    let h = (r.size.h - 2 * gap).max(1);
    Rectangle::new((r.loc.x + gap, r.loc.y + gap).into(), (w, h).into())
}

/// Hyprland-ish smart gaps: when enabled and exactly one tiled window, both gaps are 0.
pub fn effective_gaps(
    gaps_out: i32,
    gaps_in: i32,
    tiled_n: usize,
    smart_gaps: bool,
) -> (i32, i32) {
    if smart_gaps && tiled_n == 1 {
        (0, 0)
    } else {
        (gaps_out, gaps_in)
    }
}

/// Split `work_area` into `n` equal-width columns (left → right).
/// Remainder pixels go to the leftmost columns. Empty when `n == 0`
/// or the area has non-positive size.
pub fn equal_column_layout(
    work_area: Rectangle<i32, Logical>,
    n: usize,
) -> Vec<Rectangle<i32, Logical>> {
    if n == 0 || work_area.size.w <= 0 || work_area.size.h <= 0 {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(n);
    let base = work_area.size.w / n as i32;
    let rem = work_area.size.w % n as i32;
    let mut x = work_area.loc.x;
    for i in 0..n {
        let w = base + if (i as i32) < rem { 1 } else { 0 };
        out.push(Rectangle::new(
            (x, work_area.loc.y).into(),
            (w.max(1), work_area.size.h).into(),
        ));
        x += w.max(1);
    }
    out
}

/// Binary dwindle: alternate vertical then horizontal splits by depth.
/// First client takes left/top half; remainder recurse into right/bottom.
pub fn dwindle_layout(
    work_area: Rectangle<i32, Logical>,
    n: usize,
) -> Vec<Rectangle<i32, Logical>> {
    if n == 0 || work_area.size.w <= 0 || work_area.size.h <= 0 {
        return Vec::new();
    }
    dwindle_rec(work_area, n, 0)
}

fn dwindle_rec(
    area: Rectangle<i32, Logical>,
    n: usize,
    depth: usize,
) -> Vec<Rectangle<i32, Logical>> {
    if n == 0 {
        return Vec::new();
    }
    if n == 1 {
        return vec![area];
    }

    let (first, rest) = if depth % 2 == 0 {
        let left_w = (area.size.w / 2).max(1);
        let right_w = (area.size.w - left_w).max(1);
        let first = Rectangle::new(area.loc, (left_w, area.size.h).into());
        let rest = Rectangle::new(
            (area.loc.x + left_w, area.loc.y).into(),
            (right_w, area.size.h).into(),
        );
        (first, rest)
    } else {
        let top_h = (area.size.h / 2).max(1);
        let bot_h = (area.size.h - top_h).max(1);
        let first = Rectangle::new(area.loc, (area.size.w, top_h).into());
        let rest = Rectangle::new(
            (area.loc.x, area.loc.y + top_h).into(),
            (area.size.w, bot_h).into(),
        );
        (first, rest)
    };

    let mut out = Vec::with_capacity(n);
    out.push(first);
    out.extend(dwindle_rec(rest, n - 1, depth + 1));
    out
}

/// Master (index 0) left column with width `factor` of work area; stack on the right.
/// `factor` is clamped to `[0.1, 0.9]`.
pub fn master_layout(
    work_area: Rectangle<i32, Logical>,
    n: usize,
    factor: f64,
) -> Vec<Rectangle<i32, Logical>> {
    if n == 0 || work_area.size.w <= 0 || work_area.size.h <= 0 {
        return Vec::new();
    }
    if n == 1 {
        return vec![work_area];
    }

    let factor = factor.clamp(0.1, 0.9);
    let mut master_w = (f64::from(work_area.size.w) * factor).round() as i32;
    master_w = master_w.clamp(1, (work_area.size.w - 1).max(1));
    let stack_w = (work_area.size.w - master_w).max(1);
    let mut out = Vec::with_capacity(n);
    out.push(Rectangle::new(
        work_area.loc,
        (master_w, work_area.size.h).into(),
    ));

    let stack_n = n - 1;
    let base = work_area.size.h / stack_n as i32;
    let rem = work_area.size.h % stack_n as i32;
    let mut y = work_area.loc.y;
    let stack_x = work_area.loc.x + master_w;
    for i in 0..stack_n {
        let h = base + if (i as i32) < rem { 1 } else { 0 };
        out.push(Rectangle::new(
            (stack_x, y).into(),
            (stack_w, h.max(1)).into(),
        ));
        y += h.max(1);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn area(x: i32, y: i32, w: i32, h: i32) -> Rectangle<i32, Logical> {
        Rectangle::new((x, y).into(), (w, h).into())
    }

    #[test]
    fn work_area_offsets_by_exclusive_zone() {
        let output = area(0, 0, 800, 600);
        let zone = area(0, 32, 800, 536);
        let work = work_area_with_exclusive(output, zone);
        assert_eq!(work, area(0, 32, 800, 536));
    }

    #[test]
    fn work_area_with_output_offset() {
        let output = area(100, 50, 800, 600);
        let zone = area(0, 40, 800, 520);
        let work = work_area_with_exclusive(output, zone);
        assert_eq!(work, area(100, 90, 800, 520));
    }

    #[test]
    fn zero_and_one() {
        assert!(equal_column_layout(area(0, 0, 100, 50), 0).is_empty());
        let one = equal_column_layout(area(10, 20, 100, 50), 1);
        assert_eq!(one.len(), 1);
        assert_eq!(one[0], area(10, 20, 100, 50));
    }

    #[test]
    fn two_columns_split_width() {
        let tiles = equal_column_layout(area(0, 0, 100, 40), 2);
        assert_eq!(tiles.len(), 2);
        assert_eq!(tiles[0].size.w + tiles[1].size.w, 100);
        assert_eq!(tiles[0].size.h, 40);
        assert_eq!(tiles[1].size.h, 40);
        assert_eq!(tiles[0].loc, (0, 0).into());
        assert_eq!(tiles[1].loc.x, tiles[0].size.w);
    }

    #[test]
    fn three_columns_remainder_left() {
        let tiles = equal_column_layout(area(0, 0, 100, 30), 3);
        assert_eq!(tiles.len(), 3);
        let sum: i32 = tiles.iter().map(|t| t.size.w).sum();
        assert_eq!(sum, 100);
        assert_eq!(tiles[0].size.w, 34);
        assert_eq!(tiles[1].size.w, 33);
        assert_eq!(tiles[2].size.w, 33);
        assert_eq!(tiles[2].loc.x + tiles[2].size.w, 100);
    }

    #[test]
    fn dwindle_zero_one_two() {
        assert!(dwindle_layout(area(0, 0, 100, 80), 0).is_empty());
        let one = dwindle_layout(area(10, 20, 100, 80), 1);
        assert_eq!(one, vec![area(10, 20, 100, 80)]);

        let two = dwindle_layout(area(0, 0, 100, 80), 2);
        assert_eq!(two.len(), 2);
        assert_eq!(two[0], area(0, 0, 50, 80));
        assert_eq!(two[1], area(50, 0, 50, 80));
        assert_eq!(two[0].size.w + two[1].size.w, 100);
    }

    #[test]
    fn dwindle_three_recurses_horizontal() {
        let tiles = dwindle_layout(area(0, 0, 100, 80), 3);
        assert_eq!(tiles.len(), 3);
        assert_eq!(tiles[0], area(0, 0, 50, 80));
        assert_eq!(tiles[1], area(50, 0, 50, 40));
        assert_eq!(tiles[2], area(50, 40, 50, 40));
        let covered: i32 = tiles.iter().map(|t| t.size.w * t.size.h).sum();
        assert_eq!(covered, 100 * 80);
    }

    #[test]
    fn master_two_and_three() {
        let two = master_layout(area(0, 0, 100, 60), 2, 0.5);
        assert_eq!(two.len(), 2);
        assert_eq!(two[0], area(0, 0, 50, 60));
        assert_eq!(two[1], area(50, 0, 50, 60));

        let three = master_layout(area(0, 0, 100, 60), 3, 0.5);
        assert_eq!(three.len(), 3);
        assert_eq!(three[0], area(0, 0, 50, 60));
        assert_eq!(three[1].size.h + three[2].size.h, 60);
        assert_eq!(three[1].loc.x, 50);
        assert_eq!(three[2].loc.x, 50);
        assert_eq!(three[2].loc.y, three[1].loc.y + three[1].size.h);
    }

    #[test]
    fn master_factor_widens() {
        let wide = master_layout(area(0, 0, 100, 60), 2, 0.7);
        assert_eq!(wide[0].size.w, 70);
        assert_eq!(wide[1].size.w, 30);
    }

    #[test]
    fn inset_rect_gaps() {
        let r = area(0, 0, 100, 80);
        assert_eq!(inset_rect(r, 0), r);
        assert_eq!(inset_rect(r, 8), area(8, 8, 84, 64));
        let tiny = inset_rect(area(0, 0, 10, 10), 100);
        assert_eq!(tiny.size.w, 1);
        assert_eq!(tiny.size.h, 1);
    }

    #[test]
    fn effective_gaps_smart_single() {
        assert_eq!(effective_gaps(8, 4, 1, true), (0, 0));
        assert_eq!(effective_gaps(8, 4, 2, true), (8, 4));
        assert_eq!(effective_gaps(8, 4, 1, false), (8, 4));
        assert_eq!(effective_gaps(8, 4, 0, true), (8, 4));
    }
}
