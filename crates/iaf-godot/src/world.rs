//! The GDScript weapons' world frame (X east, Y north, Z up) ↔ `iaf_avionics` — the same axes.

use godot::prelude::*;
use iaf_avionics::Vec3;

pub fn vec3(v: Vector3) -> Vec3 {
    Vec3::new(v.x.into(), v.y.into(), v.z.into())
}

pub fn vector3(v: Vec3) -> Vector3 {
    Vector3::new(v.x as f32, v.y as f32, v.z as f32)
}

/// A dictionary value of type `T`, if present and convertible.
pub fn get<T: FromGodot>(d: &VarDictionary, key: &str) -> Option<T> {
    d.get(key).and_then(|v| v.try_to().ok())
}

/// A number in a dictionary, int or float.
pub fn num(d: &VarDictionary, key: &str) -> Option<f64> {
    let v = d.get(key)?;
    v.try_to::<f64>().ok().or_else(|| v.try_to::<i64>().ok().map(|i| i as f64))
}

/// The terrain height at a world point through `f` (Callable(Vector3) -> float or null); no terrain when invalid.
pub fn terrain(f: Option<Callable>) -> impl Fn(Vec3) -> Option<f64> {
    let f = f.filter(Callable::is_valid);
    move |p| f.as_ref()?.call(&[vector3(p).to_variant()]).try_to().ok()
}
