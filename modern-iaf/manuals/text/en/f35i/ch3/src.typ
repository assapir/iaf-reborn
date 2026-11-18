// Chapter 3's parts, shared by its sections: chapter 2's source and the mark of each emergency's state in the sim.
#import "/modern-iaf/manuals/text/en/f35i/ch2/src.typ": *
/// The line under an emergency's heading: whether the sim can produce it.
#let state(s) = block(above: 5pt, below: 7pt, sim-chip(s))
/// A procedure no public source gives.
#let open-proc = [The F-35's procedure is not public: open.]
