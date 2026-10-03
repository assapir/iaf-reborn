//! A 3-vector in the world frame (X east, Y north, Z up, metres).

use std::ops::{Add, AddAssign, Mul, Neg, Sub};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Vec3 {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

impl Vec3 {
    pub const ZERO: Vec3 = Vec3::new(0.0, 0.0, 0.0);
    pub const NORTH: Vec3 = Vec3::new(0.0, 1.0, 0.0);
    pub const UP: Vec3 = Vec3::new(0.0, 0.0, 1.0);

    pub const fn new(x: f64, y: f64, z: f64) -> Self {
        Vec3 { x, y, z }
    }

    pub fn dot(self, o: Vec3) -> f64 {
        self.x * o.x + self.y * o.y + self.z * o.z
    }

    pub fn cross(self, o: Vec3) -> Vec3 {
        Vec3::new(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x)
    }

    pub fn length_squared(self) -> f64 {
        self.dot(self)
    }

    pub fn length(self) -> f64 {
        self.length_squared().sqrt()
    }

    pub fn distance(self, o: Vec3) -> f64 {
        (self - o).length()
    }

    /// The unit vector, or None for the zero vector.
    pub fn try_normalize(self) -> Option<Vec3> {
        let l = self.length();
        (l > 0.0).then(|| self * (1.0 / l))
    }

    /// The horizontal part, normalized (zero when vertical, as Godot's Vector2.normalized()).
    pub fn flat_dir(self) -> Vec3 {
        Vec3::new(self.x, self.y, 0.0).try_normalize().unwrap_or(Vec3::ZERO)
    }

    /// Rotated by `angle` (rad) about the unit `axis`, right-handed (Rodrigues).
    pub fn rotated(self, axis: Vec3, angle: f64) -> Vec3 {
        let (s, c) = angle.sin_cos();
        self * c + axis.cross(self) * s + axis * (axis.dot(self) * (1.0 - c))
    }

    /// Raised by `dz` metres.
    pub fn raised(self, dz: f64) -> Vec3 {
        Vec3::new(self.x, self.y, self.z + dz)
    }
}

impl Add for Vec3 {
    type Output = Vec3;
    fn add(self, o: Vec3) -> Vec3 {
        Vec3::new(self.x + o.x, self.y + o.y, self.z + o.z)
    }
}

impl AddAssign for Vec3 {
    fn add_assign(&mut self, o: Vec3) {
        *self = *self + o;
    }
}

impl Sub for Vec3 {
    type Output = Vec3;
    fn sub(self, o: Vec3) -> Vec3 {
        Vec3::new(self.x - o.x, self.y - o.y, self.z - o.z)
    }
}

impl Mul<f64> for Vec3 {
    type Output = Vec3;
    fn mul(self, k: f64) -> Vec3 {
        Vec3::new(self.x * k, self.y * k, self.z * k)
    }
}

impl Neg for Vec3 {
    type Output = Vec3;
    fn neg(self) -> Vec3 {
        self * -1.0
    }
}
