//! Parsers for the data files of Jane's IAF: Israeli Air Force (1998).

pub mod bytes;
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

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    Format(String),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Error::Io(e) => write!(f, "I/O error: {e}"),
            Error::Format(s) => write!(f, "bad format: {s}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Io(e) => Some(e),
            Error::Format(_) => None,
        }
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e)
    }
}
