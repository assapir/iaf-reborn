//! Parsers for the data files of Jane's IAF: Israeli Air Force (1998).

pub mod emf;
pub mod esa;
pub mod ini;
pub mod iso9660;
pub mod lzo;
pub mod menu;
pub mod model;
pub mod ptt;
pub mod rtf;
pub mod winfnt;
pub mod ssf;
pub mod xfile;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("bad format: {0}")]
    Format(String),
}
