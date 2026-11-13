//! Third-party CC0 textures from ambientCG (<https://ambientcg.com/>, licence: <https://docs.ambientcg.com/license/>),
//! downloaded by setup into `assets/thirdparty/ambientcg/<id>/` (docs/rendering.md §1.4, §9, docs/credits.md). Each
//! list below is one use (Ground textures, Model detail, Scenery); `fetch` takes any list, so more uses add a list.
//!
//! Per material `fetch` downloads `<id>_2K-JPG.zip`, checks its SHA-256 against the pinned one, keeps the colour,
//! normal (OpenGL) and roughness maps, and packs them at 1024² with every mip level, compressed as the GPU reads them
//! (the game only uploads them):
//! - `albedo.bc1`: BC1 (DXT1), RGB = the colour (linear) over the material's mean colour, halved (1.0 = the mean is
//!   128): the game multiplies the imagery by it, so the photo keeps its own hue and brightness;
//! - `nr.bc3`: BC3 (DXT5), R = roughness, G = normal Y, B = the colour's brightness about its mean (0.5 = the mean,
//!   ±2 σ to 0 / 1: stains, chips, scratches; Model detail's tint), A = normal X (the DXT5 normal layout).
//!
//! A leaf set's opacity map is kept too (the trees list: `foliage.rs` composes the scenery's foliage from it).
//!
//! Then `material.json` (id, size, checksum) marks the material done, and `<list>.json` lists the list's materials.
//!
//! The scenery's sources (`SCENERY`, docs/scenery.md §1.1) are kept as they come: `fetch_files` downloads each into
//! `assets/source/scenery/` and checks its pinned SHA-256.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

use anyhow::{Context, Result, bail};
use image::{GrayImage, RgbaImage, imageops::FilterType};
use serde_json::json;
use sha2::{Digest, Sha256};
use texpresso::{Algorithm, Format, Params};

use crate::progress::{Progress, check, download_line};

/// One ambientCG material: its asset id, the SHA-256 of its `<id>_2K-JPG.zip`, the real size one texture repeat
/// covers (metres; ambientCG's dimension where it gives one, else inferred) and what the game uses it for.
pub struct Material {
    pub id: &'static str,
    pub sha256: &'static str,
    pub size_m: f32,
    pub used_for: &'static str,
}

/// The "Ground textures" materials (Graphics → MORE, terrain.gdshader), in the shader's layer order.
pub const GROUND_TEXTURES: &[Material] = &[
    Material {
        id: "Asphalt027C",
        sha256: "5c20e533bc497645f06401972abbff2b49e854b899ece727730d213973961c15",
        size_m: 2.5,
        used_for: "runways and taxiways: cracked asphalt",
    },
    Material {
        id: "Concrete040",
        sha256: "f757c69e3c9e380b76bfd9fd0641f519d3717b8ecd1dd76a99e14c3a3695dd7f",
        size_m: 1.4,
        used_for: "aprons: rough concrete",
    },
    Material {
        id: "Ground054",
        sha256: "643e7c8689bac041f17c660eff6a5459bfe0535d4466737beb0e64902b23235a",
        size_m: 3.5,
        used_for: "pale ground: sand",
    },
    Material {
        id: "Ground062L",
        sha256: "a24162411319167954438c0bf5479e38c0d9042d96eadaab4b5f05b8bd0199cb",
        size_m: 3.0,
        used_for: "grey-brown ground: gravel desert",
    },
    Material {
        id: "Ground037",
        sha256: "defa9f880ec692eb3ef5435fd7bc7b8721c0d577f7824ea18ac68537f01ab65b",
        size_m: 2.1,
        used_for: "green ground: grass and fields",
    },
    Material {
        id: "Ground109",
        sha256: "1f32c5ffa599e32c61405417d9b682dcc23e6ccc38f8a3a09880f204a481e0c8",
        size_m: 2.8,
        used_for: "brown ground: dry soil and scrub",
    },
    Material {
        id: "Rock045",
        sha256: "95f8f208d4426ab7885a896a6004a85ce83dac3e098b9790a3cd7422f2d3d021",
        size_m: 2.4,
        used_for: "steep slopes: rock",
    },
];

/// The "Model detail" materials (Graphics → MORE, shared/util/model_detail.gd), in that file's MATERIALS order: painted,
/// worn, concrete, rubber. The game sets each use's own repeat; `size_m` is the material's real size.
pub const MODEL_DETAIL: &[Material] = &[
    Material {
        id: "PaintedMetal002",
        sha256: "c95fc5a065582deded194e7bc4d9592706b58aa0259110989931ec8f8ad1a9a0",
        size_m: 1.0,
        used_for: "stores and jets: painted metal",
    },
    Material {
        id: "Metal016",
        sha256: "0fbb57ee6787731f538f711223109eb5539287f8c0eda7ccba690858c3ece213",
        size_m: 1.5,
        used_for: "vehicles, ships, metal structures: worn steel",
    },
    Material {
        id: "Concrete029",
        sha256: "7685a6a63cfd21cf737c3eae61c226dee2d9259a57aa93164bdd1b2e748afd94",
        size_m: 3.0,
        used_for: "buildings and shelters: cast concrete",
    },
    Material {
        id: "Rubber004",
        sha256: "dc1566f645f6ef7853bb3a3e7a15ef450edbb90cbd471c6097d44cd04521bea0",
        size_m: 0.5,
        used_for: "tyres: rubber",
    },
];

/// The "Scenery" wall materials (Graphics → MORE, shared/terrain/scenery.gdshader), in the shader's layer order = the
/// cell file's wall index (docs/scenery.md): plaster, stone, concrete, corrugated steel. The roof colour tints them.
pub const SCENERY_WALLS: &[Material] = &[
    Material {
        id: "Plaster003",
        sha256: "7088106ca868dab12f702c1bac8dc012f445f572a3e02d5377b42ed497be1fd8",
        size_m: 2.0,
        used_for: "houses and flats: white rough plaster",
    },
    Material {
        id: "Bricks084",
        sha256: "25d921f3acf9ed59732ae1edb1cbe478a073ccc8df1f68eee09a8b9b617758c3",
        size_m: 2.0,
        used_for: "stone-clad buildings: beige sandstone blocks (Jerusalem stone)",
    },
    Material {
        id: "Concrete034",
        sha256: "fafd7cd3aee2b703abbb12b7810ef565ab76ac7ea3b1ea9a73b088e423e670b3",
        size_m: 1.1,
        used_for: "offices and towers: cast concrete",
    },
    Material {
        id: "CorrugatedSteel005",
        sha256: "9bec057d9db923cdf2208c0cc5b41e4df2072237c951ef4a4e22db0830a2a00a",
        size_m: 2.0,
        used_for: "sheds and industry: painted corrugated steel",
    },
];

/// The scenery trees' sources (shared/terrain/scenery.gd, docs/scenery.md §3.2), in `foliage::LAYERS` order: setup
/// composes the foliage textures from their kept colour and opacity maps (`foliage::build`). `size_m`: one leaf,
/// sprig or blade, the bark's repeat.
pub const TREE_TEXTURES: &[Material] = &[
    Material {
        id: "LeafSet001",
        sha256: "26b43318e64ae442241f396309e78ee772dac53577bd92edc450d294b46ae9ba",
        size_m: 0.25,
        used_for: "broadleaf trees: small grey-green leaves (olive, carob, oak)",
    },
    Material {
        id: "LeafSet019",
        sha256: "3b2b26b9120fa29b495714f6f496ac6c51066cf0bd4bd453dd2bf587987480b5",
        size_m: 0.3,
        used_for: "pines and cypresses: needle sprigs",
    },
    Material {
        id: "Foliage001",
        sha256: "3a617bfe6abd5bcb4add69fad928e48371d02b9717802ddffbd95a9c44001c7d",
        size_m: 0.5,
        used_for: "palm fronds: long narrow blades as leaflets",
    },
    Material {
        id: "Bark012",
        sha256: "8514e883c1171f64e3190e075dd32ac60599426e5e7d4aa0271c1615ce7549c2",
        size_m: 1.0,
        used_for: "tree trunks: furrowed bark",
    },
];

/// Every list setup fetches: (name, materials). A new use adds its list here; `<dir>/<name>.json` lists it for the game.
pub const LISTS: &[(&str, &[Material])] =
    &[("ground", GROUND_TEXTURES), ("model", MODEL_DETAIL), ("scenery", SCENERY_WALLS), ("trees", TREE_TEXTURES)];

/// One downloaded file kept as it comes (the scenery's sources, docs/scenery.md §1.1): its name under the download
/// folder, where it comes from and its pinned SHA-256.
#[derive(Clone, Copy)]
pub struct Download {
    pub file: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    /// Its size, for the download's progress.
    pub bytes: u64,
}

/// The scenery's sources (`crate::scenery`), each file pinned: every install makes the same scenery.
pub const SCENERY: &[Download] = &[
    Download {
        file: "israel-and-palestine-260101.osm.pbf",
        url: "https://download.geofabrik.de/asia/israel-and-palestine-260101.osm.pbf",
        sha256: "55e33e3cdc59e65e64caf853aec0f2c9b24bc617957c942c63004520f930118d",
        bytes: 119_334_282,
    },
    Download {
        file: "ms-GazaStrip-122130000.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=GazaStrip/quadkey=122130000/part-00196-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e6e036f8f8f410aefb86189570e83892711b671bd029dba2f3d385c4afb31200",
        bytes: 7_935_192,
    },
    Download {
        file: "ms-GazaStrip-122130001.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=GazaStrip/quadkey=122130001/part-00038-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "62e1129db23fd69db92778b3739aeb3339f594f8805b0f920540eb2bcd867ebb",
        bytes: 7_171_055,
    },
    Download {
        file: "ms-GazaStrip-122130002.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=GazaStrip/quadkey=122130002/part-00008-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "129abb01b925ec614292ab6a9e9b553a4cbb7818f51b5aa61f4063c443c2487d",
        bytes: 8_405_423,
    },
    Download {
        file: "ms-Israel-122112212.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112212/part-00113-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "d82eea3612e5d0ff06b4f553c8066b0b08084b543d7e5ad4c09bbc9b91fc392e",
        bytes: 1_344_931,
    },
    Download {
        file: "ms-Israel-122112221.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112221/part-00083-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4e24c3d2cff0210da1fdd04d9915aa2bb7f9a817e55d435de36288c24a9a14e1",
        bytes: 13_886_910,
    },
    Download {
        file: "ms-Israel-122112223.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112223/part-00050-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9b3f3193d80baa215092844ca216f310bb19cbf130fd3b3fcdebf2d1c6cb0744",
        bytes: 42_306_174,
    },
    Download {
        file: "ms-Israel-122112230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112230/part-00047-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9fd87a803dfd5c691ac5a8b20203c5a2b482798a0247469c9647c63eb6201b57",
        bytes: 30_289_908,
    },
    Download {
        file: "ms-Israel-122112232.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112232/part-00088-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "bf62440a07662752ab52821d91fa0d99a6c8f4d8cdad85f8ac87fad1b45a4dab",
        bytes: 2_475_957,
    },
    Download {
        file: "ms-Israel-122130000.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130000/part-00143-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "49022dc2906bd2b80e36ad65418566cfad05838f202bbf961434c0d90123a338",
        bytes: 70_177,
    },
    Download {
        file: "ms-Israel-122130001.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130001/part-00163-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "83a94942c90fc9ba6af257d5478b511fead0174179a9371028fa61432f34f5a0",
        bytes: 28_984_586,
    },
    Download {
        file: "ms-Israel-122130002.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130002/part-00155-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "274646d283afeef02c85f23cd918838b2fc754129e8b4fae21258b7604785f36",
        bytes: 1_767_683,
    },
    Download {
        file: "ms-Israel-122130003.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130003/part-00087-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "8299f65213412d1ed5849cf149b821a803798a45ff5db6f22e9aada1b100f212",
        bytes: 18_165_663,
    },
    Download {
        file: "ms-Israel-122130010.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130010/part-00000-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "befad82cd925a5817d14b3c2c953a06df471b9f7fb4ca4f2908f8b1a857ed0cf",
        bytes: 2_512_486,
    },
    Download {
        file: "ms-Israel-122130012.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130012/part-00145-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "7e67b76ec1338117858eed083ac60f145f4607fddb7152eece30a1e7c71767c9",
        bytes: 1_905_349,
    },
    Download {
        file: "ms-Israel-122130021.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130021/part-00189-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6041a86f0ff8ffd950772dc8b9552a429fd70f3a04cb020153d5c3928d1c6a24",
        bytes: 486_633,
    },
    Download {
        file: "ms-Israel-122130023.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130023/part-00004-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "f5891fb55551c3b17bb3acb90558af8ace487a61e0b152de548f3ec418d4bf4f",
        bytes: 1_461_292,
    },
    Download {
        file: "ms-Israel-122130030.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130030/part-00049-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "702103b3fa98baa99defc4cb562447e8e3c8d96c56f95fcfbca0bd257cf6d533",
        bytes: 690_468,
    },
    Download {
        file: "ms-Israel-122130201.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130201/part-00036-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "cb09ff6fe4b25b49384c658651514dd5c870b261765f217ae970c6eea32908aa",
        bytes: 58_081,
    },
    Download {
        file: "ms-WestBank-122112223.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122112223/part-00062-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "8e126014c70a1446f8363cfae80e6293996e7ff2a036b7d43b5fbf07989dc47e",
        bytes: 13_285_218,
    },
    Download {
        file: "ms-WestBank-122112230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122112230/part-00192-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "04e3964bc559b0a52e3737b8a2c373cb0de088645c57a74109c7e5812ddf8dce",
        bytes: 776,
    },
    Download {
        file: "ms-WestBank-122112232.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122112232/part-00113-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4377638988009bae8a589b02503806267647a8fa1b89e028c3c3274c965e5007",
        bytes: 20_452_296,
    },
    Download {
        file: "ms-WestBank-122130001.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122130001/part-00018-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0d52b7a28bc3605c93f0f5bc9476700fa7628ba1bb3acafe49de6d5b621afceb",
        bytes: 18_649_529,
    },
    Download {
        file: "ms-WestBank-122130003.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122130003/part-00169-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6d9e2869ca2e5fc50320c2c0dc77ec1ba567a56da73c93b9643450b8526e9507",
        bytes: 9_445,
    },
    Download {
        file: "ms-WestBank-122130010.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122130010/part-00172-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3d5cbf64f029d91ff35113c95b241172b6cec2d9a848507e55e925caf7a4504e",
        bytes: 15_722_428,
    },
    Download {
        file: "GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R5_C22.zip",
        url: "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_BUILT_H_GLOBE_R2023A/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100/V1-0/tiles/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R5_C22.zip",
        sha256: "7d0fd7fba104af2d7421bb4f4f463c98ea0d5e05933d55a1a446dec4f2f65939",
        bytes: 10_033_383,
    },
    Download {
        file: "GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R6_C22.zip",
        url: "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_BUILT_H_GLOBE_R2023A/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100/V1-0/tiles/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R6_C22.zip",
        sha256: "c5086df9585000da29dda16e13ffbe48d108a9fa0bc419429709f7a8ca37b85c",
        bytes: 5_628_921,
    },
    Download {
        file: "eth-N27E033.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N27E033_Map.tif",
        sha256: "a04beddf060b9ae81eeb018af83118aa1fe27efd129370e2a6f8bad917493061",
        bytes: 23_739_396,
    },
    Download {
        file: "eth-N30E033.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N30E033_Map.tif",
        sha256: "70257c317658ee5a50eb2311b9e12d88701b8b5949b90c66a8ef3e71a8a0ab0d",
        bytes: 59_449_031,
    },
    Download {
        file: "eth-N33E033.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N33E033_Map.tif",
        sha256: "a83031c078015a1d7bc2a146a55ece8186440a0a6db56071ff958c2c75e0c3e6",
        bytes: 64_675_563,
    },
];

/// The scenery's sources for the rest of the theatre (`crate::scenery::build_theatre`, docs/scenery.md §1.7), each
/// optional: Microsoft's footprints of Lebanon, Syria, Jordan, Egypt and Cyprus in the zoom-9 tiles that meet the
/// theatre (release 2026-02-03), GHS-BUILT-H's two tiles west of `SCENERY`'s and ETH's canopy tiles around its three
/// (up to 36° N). The countries' OpenStreetMap extracts are `ROADS`. A change to this list bumps
/// `crate::scenery::GENERATOR` when it changes the cells' ids.
pub const SCENERY_THEATRE: &[Download] = &[
    Download {
        file: "GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R5_C21.zip",
        url: "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_BUILT_H_GLOBE_R2023A/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100/V1-0/tiles/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R5_C21.zip",
        sha256: "57b7c9fd950f7fdeb461c81f71bd447ccc5b8a8f0705e52b43cc36f519c765ce",
        bytes: 8_223_697,
    },
    Download {
        file: "GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R6_C21.zip",
        url: "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_BUILT_H_GLOBE_R2023A/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100/V1-0/tiles/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R6_C21.zip",
        sha256: "37483f991d396d167476869aa1081a06e0723d2cd01194cd2c3a10a34979f9c6",
        bytes: 6_566_494,
    },
    Download {
        file: "eth-N30E027.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N30E027_Map.tif",
        sha256: "453f1a1c1929b064cb860bd62af21444488a7e0b8f47f85f15eae3d82603f3bd",
        bytes: 17_780_434,
    },
    Download {
        file: "eth-N27E030.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N27E030_Map.tif",
        sha256: "4642b29869e65ce9ed3aeaea13709bef9ab6d64b1fede41b449b0d4b936c3f84",
        bytes: 46_260_071,
    },
    Download {
        file: "eth-N30E030.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N30E030_Map.tif",
        sha256: "37154279a53f975902ccd8d533aef9746c0abbf6f2897e6ef681ba1a673f1b10",
        bytes: 110_966_880,
    },
    Download {
        file: "eth-N33E030.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N33E030_Map.tif",
        sha256: "02d9a753f7dfa0f355115b8ef5f61cef85e0ed3381d87c68daca6b4dbb073de5",
        bytes: 23_554_498,
    },
    Download {
        file: "eth-N27E036.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N27E036_Map.tif",
        sha256: "e0ba548253c88f0f7258e2219779b6908ded6552404aa8d72b2fc7c3cb06ccda",
        bytes: 18_943_451,
    },
    Download {
        file: "eth-N30E036.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N30E036_Map.tif",
        sha256: "2b0e61ff65af184ac780c59cb54942740b7a131649b9ab08d64e53a170a4bb14",
        bytes: 17_748_296,
    },
    Download {
        file: "eth-N33E036.tif",
        url: "https://libdrive.ethz.ch/index.php/s/cO8or7iOe5dT2Rt/download?path=%2F3deg_cogs&files=ETH_GlobalCanopyHeight_10m_2020_N33E036_Map.tif",
        sha256: "f2f0a0f9edcf9cb3967c6d04da91d1828540444098994ff31925e26b4954f5f9",
        bytes: 58_849_913,
    },
    Download {
        file: "ms-Cyprus-122103121.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122103121/part-00036-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0421f04ea0e72dbb4a82fa133e50f93acdf0e026914d7cc509917c5881c66c32",
        bytes: 133_579,
    },
    Download {
        file: "ms-Cyprus-122103123.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122103123/part-00170-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6660f0e0aaee0a2d821e764e04145fd2e48f303675a399f97728ee4c4be1a6c8",
        bytes: 30_420,
    },
    Download {
        file: "ms-Cyprus-122103130.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122103130/part-00103-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "2da65ca913fb3f706f068ae29264541a4f1c4939d540a3f85fdfe38704bd13cd",
        bytes: 6_759_772,
    },
    Download {
        file: "ms-Cyprus-122103131.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122103131/part-00110-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "878d106cd9a99199babb04403b1067c54b0e74bcf5d3f31db7c7cce894878e7d",
        bytes: 32_834_494,
    },
    Download {
        file: "ms-Cyprus-122103132.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122103132/part-00128-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "50b7f1cd850711bb349bf6ece2c7df9aeeeddd850bab5dd44913e9843361d813",
        bytes: 15_249_921,
    },
    Download {
        file: "ms-Cyprus-122103133.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122103133/part-00067-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "450640ba7505c8e2531f3920d8009edbe10491886b9f1a7c29baac7549bdffae",
        bytes: 7_257_542,
    },
    Download {
        file: "ms-Cyprus-122112002.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122112002/part-00043-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "2e1e975997b9a5038f37e28e1b1057d38c56183c0beda59d2c42373ab826a88c",
        bytes: 984_635,
    },
    Download {
        file: "ms-Cyprus-122112003.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122112003/part-00034-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "b3dc9880aea5c2dbf849f7f2b0aebee2d7d32c5601aa8dfc0f603ed987c40371",
        bytes: 20_026,
    },
    Download {
        file: "ms-Cyprus-122112020.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Cyprus/quadkey=122112020/part-00068-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "ee9a9c26d9bf80f9c75cb8f90d8412404afe13a4ccac7fc283ecdc257c5b7bc1",
        bytes: 11_074_457,
    },
    Download {
        file: "ms-Egypt-122121011.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121011/part-00029-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0ff0bd6958417959bf72936a303627f576dbe1ec17d87e382d53e53c67972fbe",
        bytes: 4_821_013,
    },
    Download {
        file: "ms-Egypt-122121012.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121012/part-00119-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6695467c842ffc703ae268eb4841ec30815a667824aae018e57381aa396facd4",
        bytes: 59_725_934,
    },
    Download {
        file: "ms-Egypt-122121013.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121013/part-00170-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "92c1fb97bd4a90d738bd7854304b7253742a23d3962aed385bd967537498737d",
        bytes: 87_070_980,
    },
    Download {
        file: "ms-Egypt-122121030.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121030/part-00148-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "a9c4f48442c24a04d59d87e09492d704b27abb7d689a3bfa3de296e2a3c555ff",
        bytes: 4_590_916,
    },
    Download {
        file: "ms-Egypt-122121031.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121031/part-00039-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "1854a260fc1bb65da3a8b78653074d8c4ff9b876fe48d38934208c1338971408",
        bytes: 36_642_241,
    },
    Download {
        file: "ms-Egypt-122121032.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121032/part-00117-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e5e6f542c61414f4110d89a49a8e42dfdd4adaab1b737a8abb738464ef9a6f24",
        bytes: 775_881,
    },
    Download {
        file: "ms-Egypt-122121033.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121033/part-00195-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "26cae092cc23fb3522d4641f5f1f2ef78c80eeb64dbc8b44108259b6d6be8d77",
        bytes: 6_264_673,
    },
    Download {
        file: "ms-Egypt-122121100.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121100/part-00073-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "c6cd8ca314a6ffd567b8e77ca2374c8e10f08e97bfb021567714e5bf2ba63ae5",
        bytes: 12_788_114,
    },
    Download {
        file: "ms-Egypt-122121101.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121101/part-00168-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "535e020bb430983a5ca0d628a29c2ba3989c08269d7748a6c6bc156e5f773e9c",
        bytes: 10_185_194,
    },
    Download {
        file: "ms-Egypt-122121102.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121102/part-00172-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "8e8bf6e3db575477a86c80378a44ebf4b7962aa22837fc9da8a69ad6f05d730f",
        bytes: 102_240_922,
    },
    Download {
        file: "ms-Egypt-122121103.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121103/part-00197-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "127b2c858632a80a6e72816452ee747e01e7d86cb30997709e9e20ec2063c117",
        bytes: 48_138_626,
    },
    Download {
        file: "ms-Egypt-122121112.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121112/part-00165-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "f8d73de9914f25e9b3c0175d5fd18a4003c54ab7581974dd62af7af03ec8311a",
        bytes: 4_727_860,
    },
    Download {
        file: "ms-Egypt-122121113.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121113/part-00134-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "2b41188bbd5a65b8247ef86437b9a0a566037195c7ff2f59b605be4ea539ec2e",
        bytes: 1_547_470,
    },
    Download {
        file: "ms-Egypt-122121120.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121120/part-00137-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9edcf009102e5588c3c48efb1bbde41fded659fa8ff947bde14ff2cca1db62b4",
        bytes: 124_428_404,
    },
    Download {
        file: "ms-Egypt-122121121.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121121/part-00173-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "2bccc99af816179b66a8a9e0c1c5c19327a1f244092e025c2a34ad14880acc1c",
        bytes: 42_497_244,
    },
    Download {
        file: "ms-Egypt-122121122.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121122/part-00021-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "a9a901da4f9989b1d950d67c9526f1b937ef3b3ef78e526d0a1b819bd4a379e8",
        bytes: 99_701_482,
    },
    Download {
        file: "ms-Egypt-122121123.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121123/part-00016-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "72ff2accfbce7525d8965393da2f213e9c10e4bc8c58b69b8053d285c5cb486a",
        bytes: 5_667_105,
    },
    Download {
        file: "ms-Egypt-122121130.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121130/part-00095-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "c0368d7d770259242a2caf67cf98b6624a60f222ccc32e128e2211fd533df4ae",
        bytes: 3_143_931,
    },
    Download {
        file: "ms-Egypt-122121131.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121131/part-00058-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3ce374510b35e844d92da5a8d7fb813eca5cbfa2dec0cfb60ed9433d728625b0",
        bytes: 609_077,
    },
    Download {
        file: "ms-Egypt-122121132.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121132/part-00174-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "350354c0a242d5a3f511b4c2e6029cf2c9f0bdf83b2bd2a321e1c83739ace4c3",
        bytes: 8_159_811,
    },
    Download {
        file: "ms-Egypt-122121133.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121133/part-00019-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "8b69081efce0be49424bb97503f9938cfef2243cc28770a12da272618555b078",
        bytes: 240_852,
    },
    Download {
        file: "ms-Egypt-122121210.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121210/part-00143-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9f40af3f4ebbc81e799d4c6451219d99612b625ea963d0d2918f5637fe7c1caa",
        bytes: 331_991,
    },
    Download {
        file: "ms-Egypt-122121211.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121211/part-00050-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "20ce607e0f909f44b7cd662e62b15a990f870ef728303706a4dce05503da3b21",
        bytes: 35_782_244,
    },
    Download {
        file: "ms-Egypt-122121212.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121212/part-00041-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6a1a47e5e48912e8ce2887fee0411d7b85e5f06d0db921434c558e9313b9fde3",
        bytes: 14_484,
    },
    Download {
        file: "ms-Egypt-122121213.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121213/part-00194-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "36b3d87bcdbf81495a81e903c7b7499f3a150abb028430a760c9126937258731",
        bytes: 36_762_402,
    },
    Download {
        file: "ms-Egypt-122121230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121230/part-00107-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "dffd297dab359f6d22d22d8cc663a93ff2778c06405683544e61477612926540",
        bytes: 702,
    },
    Download {
        file: "ms-Egypt-122121231.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121231/part-00157-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "767577fe8ff17c5bf7a94958a5531b4d4713aa12b77068a20b699f4248ddb54b",
        bytes: 27_810_296,
    },
    Download {
        file: "ms-Egypt-122121233.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121233/part-00010-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "aca48131bdff60b8dadd6756279f8d1b821814b96070b936565335266514b428",
        bytes: 17_274_416,
    },
    Download {
        file: "ms-Egypt-122121300.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121300/part-00143-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "69ece31e8eefc7eb8ba76ecb91c4a1592fcc52a5531379e71c10fcb549d0f250",
        bytes: 32_280_741,
    },
    Download {
        file: "ms-Egypt-122121301.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121301/part-00018-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "bfc7a60d5bc63d1cb2d639499bbc5b63109b64626ef2b02f239f85aa42d3826c",
        bytes: 152_968,
    },
    Download {
        file: "ms-Egypt-122121302.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121302/part-00018-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "f30f1fa082e17b8a8906f810fc04bbfbc0f4cbf142f9c66c10bc59a3ea625b0c",
        bytes: 1_035_590,
    },
    Download {
        file: "ms-Egypt-122121303.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121303/part-00119-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "7d015287ef8616225355b7db7b08fa3c9e2833f62ae872c3f036d8594b846ff9",
        bytes: 74_398,
    },
    Download {
        file: "ms-Egypt-122121310.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121310/part-00142-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "61f3a7e7682af17255bd78c9de9170fefb1bfe5148c9ee722f8ad83fccfe4cf9",
        bytes: 1_850_610,
    },
    Download {
        file: "ms-Egypt-122121311.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121311/part-00156-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "c627a6b2e3668dfd43d1cddd38f24e59d8ba29077bcb559d5ffc40f1ec8aa124",
        bytes: 660_675,
    },
    Download {
        file: "ms-Egypt-122121312.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121312/part-00079-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "92e8322f517ea6e42e6c65a1e1a6f1c54548cc60e110e8e9ecf2b66729e30157",
        bytes: 240_130,
    },
    Download {
        file: "ms-Egypt-122121313.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121313/part-00016-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "61fe61ab1cafd6778c07d05895f412ed99ba28d9b3d524d79d17a6abb96bd862",
        bytes: 1_509_900,
    },
    Download {
        file: "ms-Egypt-122121320.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121320/part-00026-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "444617cab7d9113cd9bf9b9a9987634d4f896a08d7045cfdfd391e6c87d17e90",
        bytes: 154_451,
    },
    Download {
        file: "ms-Egypt-122121321.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121321/part-00085-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "afaa6fef56ea99c66bbbb57a1094a0ef86f31c4da73015dc9f9977fdfdd43dde",
        bytes: 34_379,
    },
    Download {
        file: "ms-Egypt-122121322.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121322/part-00035-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "de302a27ec241ba3d19bfb8da444c0c1ad90ac61c6afd7c37466955c802c1447",
        bytes: 20_743_189,
    },
    Download {
        file: "ms-Egypt-122121323.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121323/part-00059-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "fd103a6e3df696222f3a1c32318f0787ca8cfd30e652d0ff32d9221de7f63b36",
        bytes: 72_009,
    },
    Download {
        file: "ms-Egypt-122121330.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121330/part-00097-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3b4da14517222a25b43466d24815f2513ccd9f2802f1c394b6820b378a5479f2",
        bytes: 48_036,
    },
    Download {
        file: "ms-Egypt-122121331.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121331/part-00129-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "70f1c83896bcce32217c9d518f24ccb250797e78348448aca74bb6c233baaf26",
        bytes: 1_185_070,
    },
    Download {
        file: "ms-Egypt-122121332.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121332/part-00158-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "916da95a7beacb28541f0654c80bf1af751955a7210729b38bcf41ed4ad6e0ef",
        bytes: 40_124,
    },
    Download {
        file: "ms-Egypt-122121333.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122121333/part-00193-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "082542ff50089c116e68d15e64a5e3f248c95c8b59939dd1782d030ccdec06e7",
        bytes: 1_178_537,
    },
    Download {
        file: "ms-Egypt-122123011.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122123011/part-00133-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "606183f394f2a884163d152c280ac41cc4d7953bb7dc63d0eb7ac7f393deb7e4",
        bytes: 27_490,
    },
    Download {
        file: "ms-Egypt-122123100.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122123100/part-00020-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "5d71d762145486aef7fe782ab143c5d5ac048d521abc2925aa116d4738a67a76",
        bytes: 28_232_038,
    },
    Download {
        file: "ms-Egypt-122123101.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122123101/part-00107-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "19a77be71d0a1e5bc0314a0de2dbfa19a098f8792774b69f368567acec52469b",
        bytes: 16_152_305,
    },
    Download {
        file: "ms-Egypt-122123110.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122123110/part-00182-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "dfbd132a28074c02f88020fb382022e47302bd5a04a3e553016e81e70b3db799",
        bytes: 130_041,
    },
    Download {
        file: "ms-Egypt-122123111.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122123111/part-00127-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "535e65161f4d8674e987e76c698ccb64d01cf985254f696d976dec20899c04cc",
        bytes: 171_803,
    },
    Download {
        file: "ms-Egypt-122130002.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130002/part-00111-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "168e2c327c2445630a453f0a4b67a7da275568099fe1463dae67d76f3fd41482",
        bytes: 5_754_909,
    },
    Download {
        file: "ms-Egypt-122130003.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130003/part-00069-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "166123a2e8c8717aa7934aaac763f5347a3fd634f9a2a7b1878798e755858c6c",
        bytes: 223,
    },
    Download {
        file: "ms-Egypt-122130020.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130020/part-00027-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3221ded15f6e587975c45a89c419f7ed322ed6691e6fdb7f6e235b61b1a31519",
        bytes: 712_757,
    },
    Download {
        file: "ms-Egypt-122130021.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130021/part-00061-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e95c5cabe1b9f5d640c8a8fa311f859f91d7401c9bb0d9dfb6eba6cf6f9f045f",
        bytes: 109_652,
    },
    Download {
        file: "ms-Egypt-122130022.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130022/part-00007-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6485848ad34403c3dd9340dee4a0ac4779fd1b23a4c794736b58192c9d1595f0",
        bytes: 227_600,
    },
    Download {
        file: "ms-Egypt-122130023.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130023/part-00156-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "f632aaf241c09816c1cdcd510e9917040dadab49baba68d6e1643cabf2b6dadd",
        bytes: 171_848,
    },
    Download {
        file: "ms-Egypt-122130200.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130200/part-00109-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "a1e4a4563ace5da6e052950f773f31882bdc2e43d1b6c79c9fa91fe383cd4673",
        bytes: 106_379,
    },
    Download {
        file: "ms-Egypt-122130201.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130201/part-00184-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "a0ae9f542192a0ab097dc62028079cc256b46a5dd7e82ecc24f809d33f33e2a1",
        bytes: 1_188_008,
    },
    Download {
        file: "ms-Egypt-122130202.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130202/part-00013-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4fab3ada76ff2f6d7972559c4b181e79d1f06a0d4452d37c55de4dbeaba45948",
        bytes: 515_486,
    },
    Download {
        file: "ms-Egypt-122130203.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130203/part-00081-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "78240be78e5220237e9e545e392b3834bac56de1242e742fd1fb49e476b33cee",
        bytes: 527_180,
    },
    Download {
        file: "ms-Egypt-122130220.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130220/part-00088-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "40dba43025156c82672d30e9e9f31b5790bedd9d83158fafb80bb5be53b7e1fc",
        bytes: 2_648_132,
    },
    Download {
        file: "ms-Egypt-122130221.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130221/part-00141-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4b6da936c86b6ace2d0bad8b00ae3a7774dda4312289cd30d71afc2c4239c874",
        bytes: 353,
    },
    Download {
        file: "ms-Egypt-122130222.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122130222/part-00029-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "1eb7ecaa7d8dc370c7c24d9b7725800b799c7c0a178f16554d79d8ec5d608a3d",
        bytes: 2_595_690,
    },
    Download {
        file: "ms-Egypt-122132000.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Egypt/quadkey=122132000/part-00013-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "276846fcdbe2d539858767d9c97017624ff3122b4ff877da6b423c053714d60a",
        bytes: 1_506_118,
    },
    Download {
        file: "ms-Jordan-122112230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122112230/part-00182-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "760b5f8a534c7f45880d7c4db2391bcbed6853883f5c9f28f9e50585631b7518",
        bytes: 6_401_607,
    },
    Download {
        file: "ms-Jordan-122112231.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122112231/part-00197-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "8eba5e015de146ae4f573babef06ac0bb3c4359cb6d1feb102efe436ff349b07",
        bytes: 4_215_176,
    },
    Download {
        file: "ms-Jordan-122112232.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122112232/part-00179-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "7fbeaba7dcbdbcd2538a7cacdf6e5e6b8f0a9f7ea1edb09d9adbda66037ace29",
        bytes: 21_199_222,
    },
    Download {
        file: "ms-Jordan-122112233.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122112233/part-00085-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "cb8c6c1d09d2cc7a1d8abd0a388e0e68f7453f6176ea005357fcdbf797c12ac5",
        bytes: 38_102_989,
    },
    Download {
        file: "ms-Jordan-122112322.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122112322/part-00075-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3dab933941e81da66d3b25f16ce4204437496e2265f087dbf59388e79907d387",
        bytes: 8_748,
    },
    Download {
        file: "ms-Jordan-122112332.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122112332/part-00018-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "92d20666eb3e5a81e850729419fd1188c034f958dece54e936e653adeac45645",
        bytes: 188_403,
    },
    Download {
        file: "ms-Jordan-122130010.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130010/part-00028-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "ff6773fe7aaa31e8aef4cf84050f13ca59ef45cf43c8b03ce7cca80fdc761d2e",
        bytes: 9_561_820,
    },
    Download {
        file: "ms-Jordan-122130011.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130011/part-00044-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4af2106ba6edf097545866693a8919755fc3e21f72fbe96ee5b54ee9feb924be",
        bytes: 15_984_776,
    },
    Download {
        file: "ms-Jordan-122130012.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130012/part-00082-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9b0a0d1f3018dc74942ea876e0951554db48c76f7dc1266d18a7b936ad9942ef",
        bytes: 7_291_745,
    },
    Download {
        file: "ms-Jordan-122130013.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130013/part-00058-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "506ac8a4410ecf5b2fd3887d51ef1af03a5e5a09aaaca81e932bda7dbede40ef",
        bytes: 7_781,
    },
    Download {
        file: "ms-Jordan-122130021.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130021/part-00069-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "b1da3f74a00e150a886285f5b84bde78e2f91345ebfed6210b51872ab10e390f",
        bytes: 763,
    },
    Download {
        file: "ms-Jordan-122130023.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130023/part-00172-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "a85397e26aed98a316ebeacf29b7bb982b76a5b4ec0eea2a1161d53bea322553",
        bytes: 1_310_086,
    },
    Download {
        file: "ms-Jordan-122130030.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130030/part-00028-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "d9d6ee665343a806f8419d2e449a360c1840b0a54fac02db3553580b38abe942",
        bytes: 4_259_746,
    },
    Download {
        file: "ms-Jordan-122130031.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130031/part-00114-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "da481f59937036187d52c563dc0a3a92b56850fba70c36bd426a6cb9a3d86555",
        bytes: 37_332,
    },
    Download {
        file: "ms-Jordan-122130032.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130032/part-00073-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3947dec6d48c790d937507837506a67e56c7f540dfdef6053f906c986bfa2de3",
        bytes: 1_945_850,
    },
    Download {
        file: "ms-Jordan-122130033.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130033/part-00090-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "caf5378a75be3899647810fb495b8e89b6c4e55a923d72b585e399e8054af56c",
        bytes: 44_913,
    },
    Download {
        file: "ms-Jordan-122130100.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130100/part-00189-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "65aeedf1e2b350947c984952e4d6846dba3d6b5ba5f04454244e28dcca165c22",
        bytes: 2_046,
    },
    Download {
        file: "ms-Jordan-122130101.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130101/part-00160-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "c4a600c7a2e4264f3ea26f64ccbbe46d521590d06d352569bb51bb5972dcf31a",
        bytes: 349,
    },
    Download {
        file: "ms-Jordan-122130102.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130102/part-00019-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "b07e4bbf6fc2f316dcb78165edaa959131657e5aefd83e2e29bd53e692ce19f5",
        bytes: 26_533,
    },
    Download {
        file: "ms-Jordan-122130103.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130103/part-00127-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e882d9dbaa8cb85a590db12d26133ac713fcd187d2e32b14615913f8f2681c95",
        bytes: 3_851,
    },
    Download {
        file: "ms-Jordan-122130120.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130120/part-00076-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "1b582156bf3689d515c6bdd9f5e0f9241e896694a0a432f56624aaaf1a6491c8",
        bytes: 22_054,
    },
    Download {
        file: "ms-Jordan-122130121.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130121/part-00150-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6db7184d698a38914ad8dd75ed4f7681e151edf4ebc0402ce5ed15ce6b5326bf",
        bytes: 15_194,
    },
    Download {
        file: "ms-Jordan-122130122.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130122/part-00027-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "15b9d58e727130d9d41cfb8d55dfe3659df02e27fb42ad6f7543f2f8098307c6",
        bytes: 6_692,
    },
    Download {
        file: "ms-Jordan-122130123.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130123/part-00000-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "faed04d51b48f2b8988aac15d7b2c34f09aa95d4acf7a5922758844bf40f7789",
        bytes: 862,
    },
    Download {
        file: "ms-Jordan-122130201.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130201/part-00117-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "10f0d716545fd320d2d95529a6912b754b5b3c68a34da952b71f877003dca9dd",
        bytes: 695_131,
    },
    Download {
        file: "ms-Jordan-122130210.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130210/part-00196-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "fa6c821dee382c44ed8960d5bb14dde7694c6e7b675ac8f406c4644ad13e1bfc",
        bytes: 99_064,
    },
    Download {
        file: "ms-Jordan-122130211.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Jordan/quadkey=122130211/part-00117-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "92e03f17f5036d551c67f18ba9549e0ff306216abceabcf44ae892d52ae3ece0",
        bytes: 12_355,
    },
    Download {
        file: "ms-Lebanon-122112032.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112032/part-00155-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "93c3849c14f77564b28177787023931f875a425f4f462edda4faf33014258de7",
        bytes: 2_577_687,
    },
    Download {
        file: "ms-Lebanon-122112033.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112033/part-00196-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "064b9129d91685836eb12ef11b43548fc7245a53ac8067c8684100fbbee30e23",
        bytes: 16_695_001,
    },
    Download {
        file: "ms-Lebanon-122112122.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112122/part-00060-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "72bfac8d0dacc8b8333cbbb1c3a778cbe62a51e94e04f0c1a21457add6bfec2b",
        bytes: 7_130,
    },
    Download {
        file: "ms-Lebanon-122112203.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112203/part-00047-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "59dc33fabddd3f526623ff19fc092965917d9f831ec28980cd42838f8feefd9b",
        bytes: 220,
    },
    Download {
        file: "ms-Lebanon-122112210.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112210/part-00150-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0d7f9c56f083d806d3ca2252174151eb645751aa243538ee01ac82865209faeb",
        bytes: 25_751_711,
    },
    Download {
        file: "ms-Lebanon-122112211.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112211/part-00198-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0a82218a9d06b77dd371ab4a62a3c5a6b9ce9107eea51dc3ab4e5f98e2774900",
        bytes: 16_012_905,
    },
    Download {
        file: "ms-Lebanon-122112212.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112212/part-00132-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "65c4c99b984359fb63951e5e5e085db7cb5549fe9d6f66962b7639d126508a65",
        bytes: 29_461_897,
    },
    Download {
        file: "ms-Lebanon-122112213.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112213/part-00170-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "57f7b4e7c7cca8a2f6288697d3c597fc5d6509af6ff908aa5191638b40155943",
        bytes: 1_256_321,
    },
    Download {
        file: "ms-Lebanon-122112221.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112221/part-00067-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9e035c03cbaa16ad73e00d6a826c2972d470fb2a95782295813a1979abd4d46e",
        bytes: 115_713,
    },
    Download {
        file: "ms-Lebanon-122112230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112230/part-00086-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "a4f35c42e619fafd6c3f1289dc83ca5f3e4e4ca526126423cf7c17a233bf7894",
        bytes: 1_749_301,
    },
    Download {
        file: "ms-Lebanon-122112300.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Lebanon/quadkey=122112300/part-00185-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4b759ea146088514b397c904fd477edd2d01026c703b78f2587761efe18d6718",
        bytes: 9_245,
    },
    Download {
        file: "ms-Syria-122110322.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122110322/part-00018-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "67209957f85afc829501895ed0c9461f461575140fd7e1ff1bf9d4b5ac202a29",
        bytes: 3_711_709,
    },
    Download {
        file: "ms-Syria-122110323.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122110323/part-00007-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4575ad2e944af5a822772f8e5b8321efea9242cb2dc10afe71a839f9363232f8",
        bytes: 3_450_570,
    },
    Download {
        file: "ms-Syria-122110332.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122110332/part-00019-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4e1911fd23bbcdddfcff29ccfd53231a2dc6b581abba5ba909282a8a335f083c",
        bytes: 6_659_271,
    },
    Download {
        file: "ms-Syria-122112011.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112011/part-00005-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3e80c2d08551e9ec453b0eae57f3bfd5eaf9ce69ad5f3566d3e58845be6be748",
        bytes: 2_456_747,
    },
    Download {
        file: "ms-Syria-122112012.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112012/part-00133-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "7297bfbfcdce66350161fbf70a709c7b9c0ccd6c30208cb11769a13147e8e002",
        bytes: 4_491_974,
    },
    Download {
        file: "ms-Syria-122112013.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112013/part-00166-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "06b19112fc4b3354b35f55261dedc48118be1a15296895497cad011ec7750572",
        bytes: 17_175_957,
    },
    Download {
        file: "ms-Syria-122112031.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112031/part-00097-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e150605e9ef3920c2ac1f89a669114222599de52dfb36ea306a789af9c2c97ef",
        bytes: 31_152_371,
    },
    Download {
        file: "ms-Syria-122112033.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112033/part-00079-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "88f0fb3711d25e3c24ed8e4e97a93ba6e7fae37e48855f2ba5cf07053a0e1461",
        bytes: 20_218_702,
    },
    Download {
        file: "ms-Syria-122112100.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112100/part-00153-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e7eceb2c19d338ad2530712e2e7fb3973c5dd9ba1be374cb65b035fb2687ebe4",
        bytes: 42_017_235,
    },
    Download {
        file: "ms-Syria-122112101.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112101/part-00055-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e162a60608cd7cc126ec392491df2316d2d2bb3b953be8cbd4379a4eef5cce4f",
        bytes: 22_996_225,
    },
    Download {
        file: "ms-Syria-122112102.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112102/part-00153-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "07df0d100e189fdf5aeb76bd92e2e5ac169ca4adf0a6c47a4c61740d52a9c696",
        bytes: 23_241_336,
    },
    Download {
        file: "ms-Syria-122112103.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112103/part-00084-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6ff36303ac3555b1b5b0b26c90f2d2ef2f0e2929bbd98b37a7ad8a94ca7fbdc0",
        bytes: 2_990_712,
    },
    Download {
        file: "ms-Syria-122112110.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112110/part-00022-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0148d1a7922ac069226e449df4b101e15708ce22df2743af074021214dd0275c",
        bytes: 10_626_460,
    },
    Download {
        file: "ms-Syria-122112112.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112112/part-00198-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0ba9f090cfb2fe8e15a4a2093b69ffc79b6521c653226720a71e0029cf990bec",
        bytes: 6_188_177,
    },
    Download {
        file: "ms-Syria-122112120.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112120/part-00165-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "f7023b9b3ab7fa9987a14b42202db0d90fb1aa0e5a1bfcf27ae500f2bbc86055",
        bytes: 21_383_792,
    },
    Download {
        file: "ms-Syria-122112121.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112121/part-00140-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "af16c7c1c76bed187cffeb78a8b2e0019cf818482fb2de6adc024119102ef7e6",
        bytes: 2_127_337,
    },
    Download {
        file: "ms-Syria-122112122.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112122/part-00164-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "f71d24940774f7222f36b8f8e9536a768c43cfcf2baf1adab413acfed990fc4f",
        bytes: 16_798_790,
    },
    Download {
        file: "ms-Syria-122112123.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112123/part-00045-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "2ff5c2b725f4dfb9bca6bf6883819e80eb21de2b6eb8eaa665661ab2e9c81b03",
        bytes: 367_955,
    },
    Download {
        file: "ms-Syria-122112130.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112130/part-00009-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "b6bd788b8ebff1a1d4ffea6a79f369b87938a2ab38889ac021168807de8cd087",
        bytes: 1_516,
    },
    Download {
        file: "ms-Syria-122112132.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112132/part-00167-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "68ab52fb92c3db2c4e8d7872eb361072346f896997cc4c47e5bedbf52f4a91e6",
        bytes: 957_142,
    },
    Download {
        file: "ms-Syria-122112211.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112211/part-00126-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "59c77cae712a44073c17e7e797c81d4acf4e43de59b767e7ee588bec2b98f286",
        bytes: 2_320_792,
    },
    Download {
        file: "ms-Syria-122112212.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112212/part-00137-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "039f81fce0992f92b0dd3e5d4f6e86feb18660454f7b9122799eb3b56ef019a9",
        bytes: 294_446,
    },
    Download {
        file: "ms-Syria-122112213.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112213/part-00143-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "b7f4e02dcd6fff82a7f3d35e1af592839b5416e898a36ef7a2e874dae256d069",
        bytes: 44_417_234,
    },
    Download {
        file: "ms-Syria-122112230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112230/part-00111-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "2c36e755ccb689a1f1717f33bd321901fbcf4173b1fb523dcbd7bb07cba159e8",
        bytes: 394_416,
    },
    Download {
        file: "ms-Syria-122112231.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112231/part-00163-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "dfc41ad4e2adc963f77859943c0e3842bde4ee4a2b154d37def5f081a2491fff",
        bytes: 18_316_269,
    },
    Download {
        file: "ms-Syria-122112233.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112233/part-00195-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "ad3046bddefa4adffdff94b04ca0271b8e4f9ffb70f2377511b0f2ed8155e23e",
        bytes: 1_091_440,
    },
    Download {
        file: "ms-Syria-122112300.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112300/part-00020-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "92667a9665f3bd7f374c86011019be10d47caa900655f2afde0ea2d2594376fe",
        bytes: 7_783_909,
    },
    Download {
        file: "ms-Syria-122112302.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112302/part-00047-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "800e9ac0d1c46151e77b3eb3b3b0cad97c265051ff57dd0b35096297238cfd04",
        bytes: 2_348_774,
    },
    Download {
        file: "ms-Syria-122112310.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112310/part-00051-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "385549b364020adacf0e6f0838753eec3fdb3256db57272d0a35c77ea306a1aa",
        bytes: 113_997,
    },
    Download {
        file: "ms-Syria-122112320.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112320/part-00106-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "92b2eb7ab0e44c202148369f2517fa12eb0e55dfbd5cf54807d9dc6bb779d8c2",
        bytes: 5_897_143,
    },
    Download {
        file: "ms-Syria-122112322.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Syria/quadkey=122112322/part-00069-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "984f22da5d700f01a1d7270314f2f957511179b62913ab8a19a4c1b85fcbce27",
        bytes: 1_330_589,
    },
];

/// The road layer's other countries of the theatre (`crate::roads`, docs/scenery.md §1.1): Geofabrik's extracts of
/// 2026-01-01, each optional (a country that fails to download has no roads). Israel and Palestine come from
/// `SCENERY`.
pub const ROADS: &[Download] = &[
    Download {
        file: "lebanon-260101.osm.pbf",
        url: "https://download.geofabrik.de/asia/lebanon-260101.osm.pbf",
        sha256: "15dd91c776462e374a0f269789b2e3c6497f3f1eaca9869cd2ae565c8ee7862f",
        bytes: 51_171_498,
    },
    Download {
        file: "syria-260101.osm.pbf",
        url: "https://download.geofabrik.de/asia/syria-260101.osm.pbf",
        sha256: "095f2173b160357a3524c36af99653caac3b0856edefa7174ae22f902d94934d",
        bytes: 74_655_427,
    },
    Download {
        file: "jordan-260101.osm.pbf",
        url: "https://download.geofabrik.de/asia/jordan-260101.osm.pbf",
        sha256: "3fd948ca30bb663205d2376afea3d00a5242cf8908583c77865795fcaa104c91",
        bytes: 30_711_576,
    },
    Download {
        file: "egypt-260101.osm.pbf",
        url: "https://download.geofabrik.de/africa/egypt-260101.osm.pbf",
        sha256: "f5096d634a69d82d65ac754291bd2f3b6e8a288595e5ac0925340604d921e219",
        bytes: 173_879_163,
    },
    Download {
        file: "cyprus-260101.osm.pbf",
        url: "https://download.geofabrik.de/europe/cyprus-260101.osm.pbf",
        sha256: "29738894799e17e81c6ad39e042e478170bb9b2dd6dfa24a6db0ddbff2a34a26",
        bytes: 35_342_500,
    },
];

/// True when `<dir>/<file>.ok` records the pinned checksum (downloaded and checked before) and the file is there.
pub fn file_done(dir: &Path, d: &Download) -> bool {
    kept(dir, d.file, d.sha256)
}

/// True when `<dir>/<file>.ok` records `sha256` and the file is there: a download kept by its own name.
fn kept(dir: &Path, file: &str, sha256: &str) -> bool {
    std::fs::read_to_string(dir.join(format!("{file}.ok"))).is_ok_and(|t| t.lines().next() == Some(sha256))
        && dir.join(file).is_file()
}

/// The day (YYYY-MM-DD, UTC) `fetch_files` checked the file, from its `.ok` mark.
pub fn file_date(dir: &Path, d: &Download) -> Option<String> {
    let t = std::fs::read_to_string(dir.join(format!("{}.ok", d.file))).ok()?;
    t.lines().nth(1).map(str::to_string)
}

/// Today (UTC) as YYYY-MM-DD.
fn today() -> String {
    let days = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs() / 86400);
    // Howard Hinnant's civil_from_days.
    let z = days as i64 + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    format!("{:04}-{m:02}-{d:02}", yoe + era * 400 + (m <= 2) as i64)
}

/// Every file of `list` into `dir` (curl, so `file://` works too), checked against its pinned SHA-256; files done
/// before are kept. `FETCH_JOBS` files download at once; the progress follows the bytes on disk, with a log line every
/// `FETCH_LOG_S` seconds. Returns how many it fetched.
pub fn fetch_files(list: &[Download], dir: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<usize> {
    std::fs::create_dir_all(dir)?;
    let total: u64 = list.iter().map(|d| d.bytes).sum::<u64>().max(1);
    let next = AtomicUsize::new(0);
    let done_bytes = AtomicU64::new(0);
    let fetched = AtomicUsize::new(0);
    let slots: Vec<AtomicU64> = (0..FETCH_JOBS).map(|_| AtomicU64::new(0)).collect();
    // A failed file does not stop the others: they finish (or keep their part for the next run), and the first
    // error is returned at the end, so a retry fetches only the failed files.
    let failed: Mutex<Option<anyhow::Error>> = Mutex::new(None);
    let stop = || cancel.load(Ordering::Relaxed);
    let worker = |slot: &AtomicU64| {
        while let Some(d) = list.get(next.fetch_add(1, Ordering::Relaxed)) {
            if stop() {
                return;
            }
            match fetch_file(d.file, d.url, d.sha256, dir, slot, &stop) {
                Ok(got) => {
                    fetched.fetch_add(usize::from(got), Ordering::Relaxed);
                    done_bytes.fetch_add(d.bytes, Ordering::Relaxed);
                }
                Err(e) => {
                    pr.log(&format!("{e:#}"));
                    failed.lock().unwrap().get_or_insert(e);
                }
            }
            slot.store(0, Ordering::Relaxed);
        }
    };
    // The files kept from before count as done, not as speed.
    let kept: u64 = list.iter().filter(|d| file_done(dir, d)).map(|d| d.bytes).sum();
    pr.log(&format!(
        "{} MB to download ({} MB kept from before)",
        (total - kept.min(total)) / 1_000_000,
        kept / 1_000_000
    ));
    std::thread::scope(|sc| {
        let workers: Vec<_> = slots.iter().map(|slot| sc.spawn(|| worker(slot))).collect();
        let (t0, mut last_log) = (std::time::Instant::now(), 0u64);
        while !workers.iter().all(|w| w.is_finished()) {
            std::thread::sleep(std::time::Duration::from_millis(500));
            let now = done_bytes.load(Ordering::Relaxed) + slots.iter().map(|s| s.load(Ordering::Relaxed)).sum::<u64>();
            pr.fraction(now as f32 / total as f32);
            let secs = t0.elapsed().as_secs();
            if secs >= last_log + FETCH_LOG_S {
                last_log = secs;
                pr.log(&download_line(now, total, now.saturating_sub(kept), t0.elapsed().as_secs_f64()));
            }
        }
    });
    if let Some(e) = failed.into_inner().unwrap() {
        return Err(e);
    }
    check(cancel)?;
    Ok(fetched.into_inner())
}

/// Waits for a curl writing `part`, calling `tick` every 250 ms; `stop` kills it ("cancelled", the part kept for the
/// next run to resume). A server that cannot resume (curl 33) loses the part, so the next run starts it again.
pub(crate) fn wait_curl(
    mut child: std::process::Child,
    part: &Path,
    stop: &dyn Fn() -> bool,
    tick: &dyn Fn(),
) -> Result<std::process::ExitStatus> {
    let status = loop {
        if let Some(s) = child.try_wait()? {
            break s;
        }
        if stop() {
            let _ = child.kill();
            let _ = child.wait();
            bail!("cancelled");
        }
        tick();
        std::thread::sleep(std::time::Duration::from_millis(250));
    };
    if status.code() == Some(33) {
        let _ = std::fs::remove_file(part);
    }
    Ok(status)
}

/// curl's patience with a slow or broken connection: a transfer under 1 kB/s for 60 s is a stall, and any failure
/// (a reset connection, curl 56, too) is tried again, resuming where it stopped when `-C -` is given.
pub const CURL_PATIENCE: [&str; 9] =
    ["--speed-limit", "1000", "--speed-time", "60", "--retry", "5", "--retry-all-errors", "--connect-timeout", "30"];

/// curl's exit status in words, for the ones a download meets.
pub fn curl_error(status: std::process::ExitStatus) -> String {
    let what = match status.code() {
        Some(6 | 7) => "no connection to the server (offline?)",
        Some(22) => "the server answered with an error",
        Some(28) => "the connection stalled",
        Some(33) => "the server cannot resume the download",
        Some(35 | 60) => "the secure connection failed",
        Some(56) => "the connection was reset",
        _ => "",
    };
    match status.code() {
        Some(c) if what.is_empty() => format!("curl exit code {c}"),
        Some(c) => format!("{what}, curl exit code {c}"),
        None => format!("curl {status}"),
    }
}

/// Files downloading at once, and the seconds between `fetch_files`' progress lines.
const FETCH_JOBS: usize = 4;
pub(crate) const FETCH_LOG_S: u64 = 15;

/// One file `file` from `url` into `dir`, checked against `sha256` (`fetch_files`, an ambientCG zip): true when it was
/// downloaded, false when it was there already. `slot` follows the bytes on disk; `stop` kills curl.
fn fetch_file(
    file: &str,
    url: &str,
    sha256: &str,
    dir: &Path,
    slot: &AtomicU64,
    stop: &dyn Fn() -> bool,
) -> Result<bool> {
    if kept(dir, file, sha256) {
        return Ok(false);
    }
    let (p, part) = (dir.join(file), dir.join(format!("{file}.part")));
    // A file already there (copied in by hand) only needs its check.
    let got = !(p.is_file() && sha256_file(&p)? == sha256);
    if got {
        let child = Command::new("curl")
            .args(["-fsSL", "-C", "-"])
            .args(CURL_PATIENCE)
            .arg("-o")
            .arg(&part)
            .arg(url)
            .spawn()
            .context("running curl")?;
        let status = wait_curl(child, &part, stop, &|| {
            slot.store(std::fs::metadata(&part).map_or(0, |m| m.len()), Ordering::Relaxed)
        })?;
        if !status.success() {
            bail!("{file}: download failed ({}); run setup again to resume it", curl_error(status));
        }
        let sum = sha256_file(&part)?;
        if sum != sha256 {
            let _ = std::fs::remove_file(&part);
            bail!("{file}: checksum mismatch (got {sum}, pinned {sha256}): the file at {url} changed");
        }
        std::fs::rename(&part, &p)?;
    }
    std::fs::write(dir.join(format!("{file}.ok")), format!("{sha256}\n{}\n", today()))?;
    Ok(got)
}

/// Where ambientCG serves the zips.
pub const AMBIENTCG: &str = "https://ambientcg.com/get?file=";
/// The packed maps' side (texels).
pub const SIDE: u32 = 1024;
/// The packing's version: `material.json` records it, and a material packed by another version is packed again from
/// its kept zip.
pub const PACK: u32 = 4;

/// The lowercase hex SHA-256 of a file.
pub fn sha256_file(p: &Path) -> Result<String> {
    let mut f = std::fs::File::open(p).with_context(|| format!("{}", p.display()))?;
    let mut h = Sha256::new();
    std::io::copy(&mut f, &mut h)?;
    Ok(format!("{:x}", h.finalize()))
}

/// True when `<dir>/<id>/material.json` records this material's checksum (fetched and packed before).
pub fn is_done(dir: &Path, m: &Material) -> bool {
    std::fs::read_to_string(dir.join(m.id).join("material.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .is_some_and(|v| v["sha256"] == m.sha256 && v["pack"] == PACK && dir.join(m.id).join("nr.bc3").is_file())
}

/// The folder under `assets/` that keeps the ambientCG zips by their own names (`<id>_2K-JPG.zip`).
pub const AMBIENTCG_SOURCE: &str = "source/ambientcg";

/// The zip of `m` is kept in `src` ([`AMBIENTCG_SOURCE`]): packing it needs no network.
pub fn zip_kept(src: &Path, m: &Material) -> bool {
    kept(src, &zip_name(m), m.sha256)
}

fn zip_name(m: &Material) -> String {
    format!("{}_2K-JPG.zip", m.id)
}

/// Every material of `list` packed into `dir`, then `<dir>/<name>.json`. Each zip is kept in `src` by its own name and
/// fetched from `base` (e.g. [`AMBIENTCG`], with the zip's name appended; curl, so `file://` works too) only when it
/// is not there. Materials already done are kept. Returns how many it packed.
pub fn fetch(
    name: &str,
    list: &[Material],
    base: &str,
    src: &Path,
    dir: &Path,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<usize> {
    std::fs::create_dir_all(dir)?;
    let mut n = 0;
    let todo = list.iter().filter(|m| !is_done(dir, m)).count();
    let (t0, mut got) = (std::time::Instant::now(), 0u64);
    for (k, m) in list.iter().enumerate() {
        check(cancel)?;
        if !is_done(dir, m) {
            got += fetch_one(m, base, src, dir, pr, cancel)?;
            n += 1;
            // The sizes are not pinned: the rate, and the time left by the materials still to come.
            let secs = t0.elapsed().as_secs_f64();
            let left = std::time::Duration::from_secs_f64(secs / n as f64 * (todo - n) as f64);
            pr.log(&format!(
                "{n} of {todo} packed, {:.0} MB downloaded, {:.1} MB/s, about {} left",
                got as f64 / 1e6,
                got as f64 / 1e6 / secs.max(0.001),
                crate::progress::duration(left)
            ));
        }
        pr.fraction((k + 1) as f32 / list.len() as f32);
    }
    let mats: Vec<_> = list.iter().map(|m| json!({ "id": m.id, "size_m": m.size_m, "used_for": m.used_for })).collect();
    std::fs::write(dir.join(format!("{name}.json")), serde_json::to_string_pretty(&json!({ "materials": mats }))?)?;
    Ok(n)
}

/// One material: its zip from `src` (downloaded into it first when it is not there, `fetch_file`), packed into `dir`;
/// the bytes downloaded.
fn fetch_one(m: &Material, base: &str, src: &Path, dir: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<u64> {
    let zip_name = zip_name(m);
    let zip = src.join(&zip_name);
    let mut bytes = 0;
    if !zip_kept(src, m) {
        std::fs::create_dir_all(src)?;
        pr.log(&format!("{}: downloading {zip_name}", m.id));
        let url = format!("{base}{zip_name}");
        if fetch_file(&zip_name, &url, m.sha256, src, &AtomicU64::new(0), &|| cancel.load(Ordering::Relaxed))? {
            bytes = std::fs::metadata(&zip)?.len();
        }
    }
    unpack(m, &zip, &dir.join(m.id))?;
    Ok(bytes)
}

/// The zip's colour, normal and roughness maps into `out`, packed (module doc).
fn unpack(m: &Material, zip_path: &Path, out: &Path) -> Result<()> {
    let mut zip = zip::ZipArchive::new(std::fs::File::open(zip_path)?)?;
    std::fs::create_dir_all(out)?;
    let mut map = |kind: &str| -> Result<(PathBuf, RgbaImage)> {
        let name = format!("{}_2K-JPG_{kind}.jpg", m.id);
        let mut data = Vec::new();
        zip.by_name(&name).with_context(|| format!("{name} not in the zip"))?.read_to_end(&mut data)?;
        let p = out.join(&name);
        std::fs::write(&p, &data)?;
        let img = image::load_from_memory(&data).with_context(|| name.clone())?.to_rgba8();
        Ok((p, image::imageops::resize(&img, SIDE, SIDE, FilterType::Triangle)))
    };
    let (_, colour) = map("Color")?;
    let (_, normal) = map("NormalGL")?;
    let (_, rough) = map("Roughness")?;
    // A leaf set's cut-out, kept as it comes (foliage.rs composes the trees from it).
    let opacity = format!("{}_2K-JPG_Opacity.jpg", m.id);
    if let Ok(mut f) = zip.by_name(&opacity) {
        let mut data = Vec::new();
        f.read_to_end(&mut data)?;
        std::fs::write(out.join(&opacity), data)?;
    }
    let bright = brightness_detail(&image::DynamicImage::ImageRgba8(colour.clone()).to_luma8());
    let albedo = detail_ratio(&colour);
    let mut nr = RgbaImage::new(SIDE, SIDE);
    for (x, y, p) in nr.enumerate_pixels_mut() {
        let n = normal.get_pixel(x, y).0;
        p.0 = [rough.get_pixel(x, y).0[0], n[1], bright.get_pixel(x, y).0[0], n[0]];
    }
    std::fs::write(
        out.join("albedo.bc1"),
        compress(&mip_chain(albedo), Format::Bc1, Algorithm::ClusterFit, [1.0, 1.0, 1.0]),
    )?;
    // The normal's Y in G weighs most.
    std::fs::write(out.join("nr.bc3"), compress(&mip_chain(nr), Format::Bc3, Algorithm::ClusterFit, [0.3, 1.0, 0.5]))?;
    let meta = json!({ "id": m.id, "size_m": m.size_m, "sha256": m.sha256, "side": SIDE, "pack": PACK, "licence": "CC0 1.0",
        "source": format!("https://ambientcg.com/a/{}", m.id) });
    std::fs::write(out.join("material.json"), serde_json::to_string_pretty(&meta)?)?;
    Ok(())
}

/// sRGB `colour` as (linear colour / its mean) / 2 per channel, in 0..255 (A = 255).
pub fn detail_ratio(colour: &RgbaImage) -> RgbaImage {
    let lin = |v: u8| {
        let c = v as f64 / 255.0;
        if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
    };
    let lut: Vec<f64> = (0..=255u8).map(lin).collect();
    let mut mean = [0f64; 3];
    for p in colour.pixels() {
        (0..3).for_each(|c| mean[c] += lut[p.0[c] as usize]);
    }
    let n = (colour.width() * colour.height()).max(1) as f64;
    let mean = mean.map(|m| (m / n).max(1e-4));
    let mut out = RgbaImage::new(colour.width(), colour.height());
    for (q, p) in out.pixels_mut().zip(colour.pixels()) {
        let r = |c: usize| (lut[p.0[c] as usize] / mean[c] * 0.5 * 255.0).round().clamp(0.0, 255.0) as u8;
        q.0 = [r(0), r(1), r(2), 255];
    }
    out
}

/// The brightness about its mean: 0.5 + (v − mean) / (4 σ), clamped (±2 σ spans 0..1).
pub fn brightness_detail(g: &GrayImage) -> GrayImage {
    let n = (g.width() * g.height()).max(1) as f64;
    let mean = g.pixels().map(|p| p[0] as f64).sum::<f64>() / n;
    let var = g.pixels().map(|p| (p[0] as f64 - mean).powi(2)).sum::<f64>() / n;
    let k = 1.0 / (4.0 * var.sqrt().max(1.0));
    GrayImage::from_fn(g.width(), g.height(), |x, y| {
        let v = 0.5 + (g.get_pixel(x, y)[0] as f64 - mean) * k;
        image::Luma([(v.clamp(0.0, 1.0) * 255.0).round() as u8])
    })
}

/// Every level of `levels` compressed as `format` with `algorithm` (block weights `w` for R, G, B), concatenated
/// (Godot's `Image.create_from_data` layout for a compressed image with mipmaps).
pub fn compress(levels: &[RgbaImage], format: Format, algorithm: Algorithm, w: [f32; 3]) -> Vec<u8> {
    let params = Params { algorithm, weights: w, weigh_colour_by_alpha: false };
    let mut out = Vec::new();
    for l in levels {
        let (wd, ht) = (l.width() as usize, l.height() as usize);
        let mut buf = vec![0u8; format.compressed_size(wd, ht)];
        format.compress(l.as_raw(), wd, ht, params, &mut buf);
        out.extend_from_slice(&buf);
    }
    out
}

/// The image and every 2×2 box-filtered level down to 1×1.
pub fn mip_chain(mut img: RgbaImage) -> Vec<RgbaImage> {
    let mut out = vec![img.clone()];
    while img.width() > 1 || img.height() > 1 {
        let (w, h) = ((img.width() / 2).max(1), (img.height() / 2).max(1));
        let mut next = RgbaImage::new(w, h);
        for (x, y, p) in next.enumerate_pixels_mut() {
            let mut s = [0u32; 4];
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let q = img.get_pixel((2 * x + dx).min(img.width() - 1), (2 * y + dy).min(img.height() - 1)).0;
                (0..4).for_each(|c| s[c] += q[c] as u32);
            }
            p.0 = s.map(|v| ((v + 2) / 4) as u8);
        }
        out.push(next.clone());
        img = next;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::progress::Stdout;
    use std::io::Write;

    /// A fake material zip (8×8 maps) in a fresh folder; returns (folder, zip path).
    fn fake_zip(tag: &str) -> (PathBuf, PathBuf) {
        let d = std::env::temp_dir().join(format!("iaf-thirdparty-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("src")).unwrap();
        let zp = d.join("src/Fake001_2K-JPG.zip");
        let mut z = zip::ZipWriter::new(std::fs::File::create(&zp).unwrap());
        for kind in ["Color", "NormalGL", "Roughness"] {
            let mut jpg = Vec::new();
            image::RgbImage::from_pixel(8, 8, image::Rgb([128, 100, 200]))
                .write_to(&mut std::io::Cursor::new(&mut jpg), image::ImageFormat::Jpeg)
                .unwrap();
            z.start_file(format!("Fake001_2K-JPG_{kind}.jpg"), zip::write::SimpleFileOptions::default()).unwrap();
            z.write_all(&jpg).unwrap();
        }
        z.finish().unwrap();
        (d, zp)
    }

    #[test]
    fn detail_ratio_maps_the_mean_to_half() {
        let mut img = RgbaImage::from_pixel(2, 1, image::Rgba([60, 60, 60, 255]));
        img.put_pixel(1, 0, image::Rgba([200, 200, 200, 255]));
        let r = detail_ratio(&img);
        let (a, b) = (r.get_pixel(0, 0).0[0] as u32, r.get_pixel(1, 0).0[0] as u32);
        assert!((a + b).abs_diff(255) <= 1 && a < b, "{a} {b}");
    }

    #[test]
    fn mip_chain_has_every_level() {
        let v = mip_chain(RgbaImage::from_pixel(4, 4, image::Rgba([10, 20, 30, 40])));
        assert_eq!(v.iter().map(|l| l.width()).collect::<Vec<_>>(), [4, 2, 1]);
        assert_eq!(v[2].get_pixel(0, 0).0, [10, 20, 30, 40]);
        // BC1: 8 bytes per 4×4 block, a level under 4 px one block.
        assert_eq!(compress(&v, Format::Bc1, Algorithm::ClusterFit, [1.0; 3]).len(), 3 * 8);
    }

    #[test]
    fn fetch_checks_the_pinned_checksum() {
        let (d, zp) = fake_zip("sum");
        let sum = sha256_file(&zp).unwrap();
        let base = format!("file://{}/", zp.parent().unwrap().display());
        let (kept, out) = (d.join("source"), d.join("out"));
        let no = AtomicBool::new(false);
        let bad = [Material { id: "Fake001", sha256: "00", size_m: 2.0, used_for: "test" }];
        let e = fetch("test", &bad, &base, &kept, &out, &Stdout, &no).unwrap_err();
        assert!(format!("{e:#}").contains("checksum mismatch"), "{e:#}");
        assert!(!out.join("Fake001/material.json").exists() && !kept.join("Fake001_2K-JPG.zip.part").exists());

        let sum: &'static str = Box::leak(sum.into_boxed_str());
        let good = [Material { id: "Fake001", sha256: sum, size_m: 2.0, used_for: "test" }];
        assert_eq!(fetch("test", &good, &base, &kept, &out, &Stdout, &no).unwrap(), 1);
        let nr = std::fs::read(out.join("Fake001/nr.bc3")).unwrap();
        assert_eq!(nr.len(), (0..=10).map(|k| 16 * ((SIDE as usize >> k).div_ceil(4)).pow(2)).sum::<usize>());
        assert!(out.join("Fake001/Fake001_2K-JPG_Color.jpg").is_file() && out.join("test.json").is_file());
        assert!(zip_kept(&kept, &good[0]), "the zip kept by its own name");
        // Done before: kept, nothing fetched (the source may be gone).
        std::fs::remove_file(&zp).unwrap();
        assert_eq!(fetch("test", &good, &base, &kept, &out, &Stdout, &no).unwrap(), 0);
        std::fs::remove_dir_all(&d).unwrap();
    }

    /// New packing code (another `PACK`) packs the material again from its kept zip: no download, no connection
    /// (the server here is a port nothing answers on).
    #[test]
    fn a_new_pack_reuses_the_kept_zip() {
        let (d, zp) = fake_zip("repack");
        let sum: &'static str = Box::leak(sha256_file(&zp).unwrap().into_boxed_str());
        let m = [Material { id: "Fake001", sha256: sum, size_m: 2.0, used_for: "test" }];
        let (kept, out, no) = (d.join("source"), d.join("out"), AtomicBool::new(false));
        std::fs::create_dir_all(&kept).unwrap();
        std::fs::copy(&zp, kept.join("Fake001_2K-JPG.zip")).unwrap();
        std::fs::create_dir_all(out.join("Fake001")).unwrap();
        std::fs::write(out.join("Fake001/nr.bc3"), "old").unwrap();
        let old = json!({ "sha256": sum, "pack": PACK - 1 });
        std::fs::write(out.join("Fake001/material.json"), old.to_string()).unwrap();
        assert!(!is_done(&out, &m[0]));
        assert_eq!(fetch("test", &m, "http://127.0.0.1:9/", &kept, &out, &Stdout, &no).unwrap(), 1);
        assert!(is_done(&out, &m[0]) && zip_kept(&kept, &m[0]));
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn fetch_files_checks_and_keeps() {
        let (d, zp) = fake_zip("files");
        let url: &'static str = Box::leak(format!("file://{}", zp.display()).into_boxed_str());
        let sum: &'static str = Box::leak(sha256_file(&zp).unwrap().into_boxed_str());
        let out = d.join("out");
        let no = AtomicBool::new(false);
        let bad = [Download { file: "a.zip", url, sha256: "00", bytes: 1 }];
        assert!(format!("{:#}", fetch_files(&bad, &out, &Stdout, &no).unwrap_err()).contains("checksum mismatch"));
        assert!(!out.join("a.zip").exists() && !out.join("a.zip.part").exists());
        let good = [Download { file: "a.zip", url, sha256: sum, bytes: 1 }];
        assert_eq!(fetch_files(&good, &out, &Stdout, &no).unwrap(), 1);
        assert!(file_done(&out, &good[0]) && file_date(&out, &good[0]).is_some_and(|d| d.len() == 10));
        assert_eq!(fetch_files(&good, &out, &Stdout, &no).unwrap(), 0, "kept");
        // A kept source opens no connection (a code change never re-downloads): its URL is never asked.
        let offline = [Download { file: "a.zip", url: "http://127.0.0.1:9/never", sha256: sum, bytes: 1 }];
        assert_eq!(fetch_files(&offline, &out, &Stdout, &no).unwrap(), 0, "kept, no connection");
        // A run after an incomplete one: the kept file opens no connection, only the missing one is fetched.
        let next = [offline[0], Download { file: "m.zip", url, sha256: sum, bytes: 1 }];
        assert_eq!(fetch_files(&next, &out, &Stdout, &no).unwrap(), 1, "only the missing file");
        assert!(file_done(&out, &next[1]));
        // A failed file leaves the others to finish: the next try fetches only the failed one.
        let mixed = [
            Download { file: "x.zip", url, sha256: "00", bytes: 1 },
            Download { file: "b.zip", url, sha256: sum, bytes: 1 },
            Download { file: "c.zip", url, sha256: sum, bytes: 1 },
        ];
        assert!(fetch_files(&mixed, &out, &Stdout, &no).is_err());
        assert!(file_done(&out, &mixed[1]) && file_done(&out, &mixed[2]), "the good files done despite x.zip");
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn brightness_detail_centres_on_the_mean() {
        let g = GrayImage::from_fn(4, 1, |x, _| image::Luma([[100, 100, 140, 60][x as usize]]));
        let d = brightness_detail(&g);
        // mean 100, σ = √800 ≈ 28.3: ±40 is ±1.41 σ → 0.5 ± 0.354
        assert_eq!([0, 2, 3].map(|x| d.get_pixel(x, 0)[0]), [128, 218, 37]);
    }

    #[test]
    fn every_list_is_pinned() {
        let mut ids: Vec<_> = LISTS.iter().flat_map(|(_, l)| l.iter().map(|m| m.id)).collect();
        ids.sort();
        ids.dedup();
        assert_eq!(ids.len(), LISTS.iter().map(|(_, l)| l.len()).sum::<usize>(), "a material in two lists");
        let mut files: Vec<_> = SCENERY.iter().chain(SCENERY_THEATRE).map(|d| d.file).collect();
        files.sort();
        files.dedup();
        assert_eq!(files.len(), SCENERY.len() + SCENERY_THEATRE.len(), "a scenery file twice");
        for d in SCENERY.iter().chain(SCENERY_THEATRE) {
            assert!(d.sha256.len() == 64 && d.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "{}", d.file);
            assert!(d.url.starts_with("https://") && !d.file.contains('/'), "{}", d.file);
        }
        for m in LISTS.iter().flat_map(|(_, l)| l.iter()) {
            assert!(m.sha256.len() == 64 && m.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "{}", m.id);
            assert!(m.size_m >= 0.25 && m.size_m < 10.0, "{}", m.id);
        }
    }
}
