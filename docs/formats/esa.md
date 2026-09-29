# setup.esa — EA installer archive

Found on the CD root (161 MB). Holds every installed file except the terrain (`Resource/Terrain/Map.ptt`),
movies (`resource/avi`) and help files, which the installer copies straight from the CD.

All integers little-endian.

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

PKWA streams start with `00 06` (binary literals, 4 KiB dictionary) and decode with zlib's `blast.c`
algorithm (Rust: `explode` crate).

## Group → folder
Defined by `INSTALL_FILES "*", "<GROUP>", "[INSTALL_PATH]\<dir>"` lines in `FINSTALL.SSF`.
Groups not listed there (`SETUP_SPECIAL_FILES`, `SYS_EXECUTABLE_GROUP`, `REMOVER_GROUP`) are installer internals.

3404 entries, 258 MB uncompressed (v1.0, 11.8.98).
