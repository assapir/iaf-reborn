//! A small behaviour tree (modern-iaf/docs/ai-plan.md §3): stateless nodes ticked from the root at each decision; the
//! memory lives in the context the tree is ticked on.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Success,
    Failure,
    Running,
}

pub enum Node<C> {
    /// The children in order until one does not fail; it decides.
    Sel(Vec<Node<C>>),
    /// The children in order while each succeeds; the first that does not decides.
    Seq(Vec<Node<C>>),
    Cond(fn(&C) -> bool),
    Act(fn(&mut C) -> Status),
}

impl<C> Node<C> {
    pub fn tick(&self, c: &mut C) -> Status {
        match self {
            Node::Sel(v) => v.iter().map(|n| n.tick(c)).find(|s| *s != Status::Failure).unwrap_or(Status::Failure),
            Node::Seq(v) => v.iter().map(|n| n.tick(c)).find(|s| *s != Status::Success).unwrap_or(Status::Success),
            Node::Cond(f) => {
                if f(c) {
                    Status::Success
                } else {
                    Status::Failure
                }
            }
            Node::Act(f) => f(c),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Node::*;
    use super::*;

    #[test]
    fn selector_and_sequence() {
        // The context: a log of the actions run and a switch.
        type C = (Vec<u8>, bool);
        let tree: Node<C> = Sel(vec![
            Seq(vec![
                Cond(|c| c.1),
                Act(|c| {
                    c.0.push(1);
                    Status::Running
                }),
            ]),
            Act(|c| {
                c.0.push(2);
                Status::Failure
            }),
            Act(|c| {
                c.0.push(3);
                Status::Success
            }),
            Act(|c| {
                c.0.push(4);
                Status::Success
            }),
        ]);
        let mut c = (Vec::new(), true);
        assert_eq!(tree.tick(&mut c), Status::Running);
        assert_eq!(c.0, [1]);
        let mut c = (Vec::new(), false);
        assert_eq!(tree.tick(&mut c), Status::Success);
        assert_eq!(c.0, [2, 3], "a failing action falls through; a success stops the selector");
    }
}
