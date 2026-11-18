// Chapter 3's parts, shared by its sections: chapter 1's sources and the mark of each emergency's state in the sim.
#import "/modern-iaf/manuals/text/en/f16/ch1/src.typ": *
/// The line under an emergency's heading: whether the sim can produce it.
#let state(s) = block(above: 5pt, below: 7pt, sim-chip(s))
#let hot-limit = if sufa { [800~°C] } else { [935~°C] }
#let light-off = if sufa { [20] } else { [10] }
