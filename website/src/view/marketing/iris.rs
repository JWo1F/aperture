//! The geometry of a six-bladed iris, shared by the mark and the hero.
//!
//! The opening is a regular hexagon. Every blade edge is one hexagon side
//! carried on past its far vertex until it meets the housing, which is what
//! turns six straight lines into a pinwheel; a blade is the region between two
//! neighbouring edges.

use std::f64::consts::PI;

pub const BLADES: usize = 6;

#[derive(Clone, Copy)]
pub struct Point(pub f64, pub f64);

pub struct Iris {
    pub center: f64,
    pub housing: f64,
    pub opening: f64,
    /// Rotation of the opening, in degrees — the "how far open" dial.
    pub twist: f64,
}

impl Iris {
    fn vertex(&self, i: usize) -> Point {
        let a = (i as f64 * 60.0 + self.twist) * PI / 180.0;
        Point(self.center + self.opening * a.cos(), self.center + self.opening * a.sin())
    }

    /// Where the edge from vertex `i` through vertex `i + 1` meets the housing.
    fn edge_end(&self, i: usize) -> Point {
        let Point(ax, ay) = self.vertex(i);
        let Point(bx, by) = self.vertex((i + 1) % BLADES);
        let (len, mut dx, mut dy) = {
            let (dx, dy) = (bx - ax, by - ay);
            let len = (dx * dx + dy * dy).sqrt();
            (len, dx, dy)
        };
        dx /= len;
        dy /= len;
        // Solve |b + t·d − c| = housing for the positive t.
        let (px, py) = (bx - self.center, by - self.center);
        let half_b = px * dx + py * dy;
        let c = px * px + py * py - self.housing * self.housing;
        let t = -half_b + (half_b * half_b - c).sqrt();
        Point(bx + t * dx, by + t * dy)
    }

    /// The six edges as one stroked path: the mark's line drawing.
    pub fn edges(&self) -> String {
        (0..BLADES)
            .map(|i| {
                let Point(ax, ay) = self.vertex(i);
                let Point(ex, ey) = self.edge_end(i);
                format!("M{ax:.3} {ay:.3}L{ex:.3} {ey:.3}")
            })
            .collect()
    }

    /// Blade `i` as a closed filled path.
    pub fn blade(&self, i: usize) -> String {
        let next = (i + 1) % BLADES;
        let Point(v1x, v1y) = self.vertex(next);
        let Point(e0x, e0y) = self.edge_end(i);
        let Point(e1x, e1y) = self.edge_end(next);
        let Point(v2x, v2y) = self.vertex((i + 2) % BLADES);
        let r = self.housing;
        format!("M{v1x:.3} {v1y:.3}L{e0x:.3} {e0y:.3}A{r} {r} 0 0 1 {e1x:.3} {e1y:.3}L{v2x:.3} {v2y:.3}Z")
    }

    pub fn blades(&self) -> impl Iterator<Item = (usize, String)> + '_ {
        (0..BLADES).map(|i| (i, self.blade(i)))
    }
}
