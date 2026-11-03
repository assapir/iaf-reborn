//! The IAF 2026 sim's own six-degrees-of-freedom flight model (item C2, iaf-2026/docs/flight-model.md §9).
//!
//! * [`tables`]: NASA TP-1538's aerodynamic data (Table III), transcribed from the report's scan.
//! * [`aero`]: the report's coefficient build-up (appendix B) over those tables.
//! * [`body`]: a quaternion rigid body with a fixed-step RK4 integrator.
//!
//! Frames: body axes x forward, y right, z down; the world is flat-earth north-east-down (NED). The game's frame
//! (ENU, [`crate::Vec3`]) is the caller's conversion: (east, north, up) = (y, x, −z). The original game's model
//! (`crate::Aircraft`) never reaches this module.

pub mod aero;
pub mod body;
pub mod engine;
pub mod gear;
pub mod jets;
pub mod tables;

pub use aero::{Coeffs, Flow, Surfaces, coefficients};
pub use body::{Airframe, Body, Quat};

pub use crate::units::{FT, G, LB, LBF, SLUG_FT2};
