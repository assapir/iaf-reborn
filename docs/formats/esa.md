# setup.esa — EA installer archive

`setup.esa` is the Electronic Arts (EA) installer archive on the CD root (161 MB). It holds every installed file except
three sets that the installer copies straight from the CD:

- the terrain (`Resource/Terrain/Map.ptt`);
- the movies (`resource/avi`);
- the help files.

The archive is a header string followed by a directory of entries, then the file data. All integers are
little-endian. Parser: `crates/iaf-formats/src/esa.rs`.

```
"ELECTRONIC_ARTS_ARCHIVE_FILE\0"
repeat:
  name      cstring            file name (8.3 or long, upper case), empty name = end of directory
  group     cstring            install group, e.g. RESOURCES_3D_CPLANES_F16_GROUP
  flags     u32                0x211 normally, 0x221 for system files
  size      u32                uncompressed size
  mtime     u32                unix time
  method    cstring            "PKWA" = PKWARE DCL implode, "NULL" = stored
  packed    u32                size in archive
  offset    u32                absolute offset of the data
<file data>
```

Each entry's `method` says how its data is stored:

- `"NULL"`: stored as is.
- `"PKWA"`: compressed with PKWARE DCL implode. A PKWA stream starts with `00 06` (binary literals, 4 KiB
  dictionary). It decodes with the algorithm of zlib's `blast.c` (in Rust: the `explode` crate).

## Group → folder
Each entry's install group decides its folder on disk. `FINSTALL.SSF` maps the groups with lines of the form
`INSTALL_FILES "*", "<GROUP>", "[INSTALL_PATH]\<dir>"`. Three groups have no such line: `SETUP_SPECIAL_FILES`,
`SYS_EXECUTABLE_GROUP` and `REMOVER_GROUP`. They are installer internals.

The v1.0 archive (11.8.98) has 3404 entries, 258 MB uncompressed.
