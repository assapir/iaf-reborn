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
//! Then `material.json` (id, size, checksum) marks the material done, and `<list>.json` lists the list's materials.
//!
//! The scenery's sources (`SCENERY`, docs/scenery.md §1.1) are kept as they come: `fetch_files` downloads each into
//! `assets/source/scenery/` and checks its pinned SHA-256.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use image::{GrayImage, RgbaImage, imageops::FilterType};
use serde_json::json;
use sha2::{Digest, Sha256};
use texpresso::{Algorithm, Format, Params};

use crate::progress::{Progress, check};

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

/// The "Model detail" materials (Graphics → MORE, game/util/model_detail.gd), in that file's MATERIALS order: painted,
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

/// The "Scenery" wall materials (Graphics → MORE, game/terrain/scenery.gdshader), in the shader's layer order = the
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

/// Every list setup fetches: (name, materials). A new use adds its list here; `<dir>/<name>.json` lists it for the game.
pub const LISTS: &[(&str, &[Material])] =
    &[("ground", GROUND_TEXTURES), ("model", MODEL_DETAIL), ("scenery", SCENERY_WALLS)];

/// One downloaded file kept as it comes (the scenery's sources, docs/scenery.md §1.1): its name under the download
/// folder, where it comes from and its pinned SHA-256.
pub struct Download {
    pub file: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
}

/// The scenery's sources (`crate::scenery`), each file pinned: every install makes the same scenery.
pub const SCENERY: &[Download] = &[
    Download {
        file: "israel-and-palestine-260101.osm.pbf",
        url: "https://download.geofabrik.de/asia/israel-and-palestine-260101.osm.pbf",
        sha256: "55e33e3cdc59e65e64caf853aec0f2c9b24bc617957c942c63004520f930118d",
    },
    Download {
        file: "ms-GazaStrip-122130000.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=GazaStrip/quadkey=122130000/part-00196-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "e6e036f8f8f410aefb86189570e83892711b671bd029dba2f3d385c4afb31200",
    },
    Download {
        file: "ms-GazaStrip-122130001.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=GazaStrip/quadkey=122130001/part-00038-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "62e1129db23fd69db92778b3739aeb3339f594f8805b0f920540eb2bcd867ebb",
    },
    Download {
        file: "ms-GazaStrip-122130002.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=GazaStrip/quadkey=122130002/part-00008-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "129abb01b925ec614292ab6a9e9b553a4cbb7818f51b5aa61f4063c443c2487d",
    },
    Download {
        file: "ms-Israel-122112212.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112212/part-00113-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "d82eea3612e5d0ff06b4f553c8066b0b08084b543d7e5ad4c09bbc9b91fc392e",
    },
    Download {
        file: "ms-Israel-122112221.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112221/part-00083-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4e24c3d2cff0210da1fdd04d9915aa2bb7f9a817e55d435de36288c24a9a14e1",
    },
    Download {
        file: "ms-Israel-122112223.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112223/part-00050-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9b3f3193d80baa215092844ca216f310bb19cbf130fd3b3fcdebf2d1c6cb0744",
    },
    Download {
        file: "ms-Israel-122112230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112230/part-00047-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "9fd87a803dfd5c691ac5a8b20203c5a2b482798a0247469c9647c63eb6201b57",
    },
    Download {
        file: "ms-Israel-122112232.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122112232/part-00088-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "bf62440a07662752ab52821d91fa0d99a6c8f4d8cdad85f8ac87fad1b45a4dab",
    },
    Download {
        file: "ms-Israel-122130000.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130000/part-00143-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "49022dc2906bd2b80e36ad65418566cfad05838f202bbf961434c0d90123a338",
    },
    Download {
        file: "ms-Israel-122130001.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130001/part-00163-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "83a94942c90fc9ba6af257d5478b511fead0174179a9371028fa61432f34f5a0",
    },
    Download {
        file: "ms-Israel-122130002.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130002/part-00155-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "274646d283afeef02c85f23cd918838b2fc754129e8b4fae21258b7604785f36",
    },
    Download {
        file: "ms-Israel-122130003.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130003/part-00087-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "8299f65213412d1ed5849cf149b821a803798a45ff5db6f22e9aada1b100f212",
    },
    Download {
        file: "ms-Israel-122130010.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130010/part-00000-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "befad82cd925a5817d14b3c2c953a06df471b9f7fb4ca4f2908f8b1a857ed0cf",
    },
    Download {
        file: "ms-Israel-122130012.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130012/part-00145-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "7e67b76ec1338117858eed083ac60f145f4607fddb7152eece30a1e7c71767c9",
    },
    Download {
        file: "ms-Israel-122130021.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130021/part-00189-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6041a86f0ff8ffd950772dc8b9552a429fd70f3a04cb020153d5c3928d1c6a24",
    },
    Download {
        file: "ms-Israel-122130023.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130023/part-00004-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "f5891fb55551c3b17bb3acb90558af8ace487a61e0b152de548f3ec418d4bf4f",
    },
    Download {
        file: "ms-Israel-122130030.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130030/part-00049-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "702103b3fa98baa99defc4cb562447e8e3c8d96c56f95fcfbca0bd257cf6d533",
    },
    Download {
        file: "ms-Israel-122130201.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=Israel/quadkey=122130201/part-00036-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "cb09ff6fe4b25b49384c658651514dd5c870b261765f217ae970c6eea32908aa",
    },
    Download {
        file: "ms-WestBank-122112223.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122112223/part-00062-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "8e126014c70a1446f8363cfae80e6293996e7ff2a036b7d43b5fbf07989dc47e",
    },
    Download {
        file: "ms-WestBank-122112230.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122112230/part-00192-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "04e3964bc559b0a52e3737b8a2c373cb0de088645c57a74109c7e5812ddf8dce",
    },
    Download {
        file: "ms-WestBank-122112232.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122112232/part-00113-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "4377638988009bae8a589b02503806267647a8fa1b89e028c3c3274c965e5007",
    },
    Download {
        file: "ms-WestBank-122130001.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122130001/part-00018-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "0d52b7a28bc3605c93f0f5bc9476700fa7628ba1bb3acafe49de6d5b621afceb",
    },
    Download {
        file: "ms-WestBank-122130003.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122130003/part-00169-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "6d9e2869ca2e5fc50320c2c0dc77ec1ba567a56da73c93b9643450b8526e9507",
    },
    Download {
        file: "ms-WestBank-122130010.csv.gz",
        url: "https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/RegionName=WestBank/quadkey=122130010/part-00172-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz",
        sha256: "3d5cbf64f029d91ff35113c95b241172b6cec2d9a848507e55e925caf7a4504e",
    },
    Download {
        file: "GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R5_C22.zip",
        url: "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_BUILT_H_GLOBE_R2023A/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100/V1-0/tiles/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R5_C22.zip",
        sha256: "3c89e8690b0c93eead634bfd2f8283dbbe8b05fb64430e701b11c7f3d8fb248b",
    },
    Download {
        file: "GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R6_C22.zip",
        url: "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_BUILT_H_GLOBE_R2023A/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100/V1-0/tiles/GHS_BUILT_H_ANBH_E2018_GLOBE_R2023A_54009_100_V1_0_R6_C22.zip",
        sha256: "c5086df9585000da29dda16e13ffbe48d108a9fa0bc419429709f7a8ca37b85c",
    },
    Download {
        file: "chm-122112212.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122112212.tif",
        sha256: "983fa447765586a8a532625ff53c1214b388e052b06f38a1e91d31046ebbbc0d",
    },
    Download {
        file: "chm-122112221.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122112221.tif",
        sha256: "39b42ba0b90078e55c1406f92c6a12825ddd5533862e153a889a818a6db6d2a9",
    },
    Download {
        file: "chm-122112223.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122112223.tif",
        sha256: "0c9b44ae413ae758760f5902be62691d4624a2711301588a5e273128baff1c56",
    },
    Download {
        file: "chm-122112230.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122112230.tif",
        sha256: "5f7835ac6f9bf9d304399febef58b1e0a0069208745ab5ff7a156875d68b8c35",
    },
    Download {
        file: "chm-122112232.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122112232.tif",
        sha256: "d139edc08d6370bdf3ea68985d03cdb15e1c5de9fbcf39aaf850a4f9507a8d9d",
    },
    Download {
        file: "chm-122130000.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130000.tif",
        sha256: "f6a5651e43e0a158d160bb637c90e3874210a2b5c87e6b428c688e3147be0ee6",
    },
    Download {
        file: "chm-122130001.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130001.tif",
        sha256: "b5dcd06734701de99b92b7f380da5109b90872d3acb2d382218bec76095cd317",
    },
    Download {
        file: "chm-122130002.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130002.tif",
        sha256: "360a8ad53c0e9573f4144d504c28ae310af1d1a6eec001ab8f8a58acd478415d",
    },
    Download {
        file: "chm-122130003.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130003.tif",
        sha256: "e8b8bce2750a55476e7000d1a1417ae416cd7ec4980f82c11aeac99f98a27698",
    },
    Download {
        file: "chm-122130010.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130010.tif",
        sha256: "f0616826d3129261ae36897d681d9508c20cb37bb9e848d7a38b219a619d17d8",
    },
    Download {
        file: "chm-122130012.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130012.tif",
        sha256: "034bcf4e0b5f5dcba347cfd9f627a0aff83705c439b60e2286ab5eef70237acb",
    },
    Download {
        file: "chm-122130020.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130020.tif",
        sha256: "45d7ccaf32363c2b9c2ae655da15c73db8f0d406321badaa40bfdf3a5391218f",
    },
    Download {
        file: "chm-122130021.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130021.tif",
        sha256: "076943ddb28ced04f68a332c57bf3b688f604c6cb65b59c3ad63ccb9619d771c",
    },
    Download {
        file: "chm-122130023.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130023.tif",
        sha256: "c7a46d54abc59b7320f9bdf3cdaf3ee120203e67a070e186135f66e0803dfdce",
    },
    Download {
        file: "chm-122130030.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130030.tif",
        sha256: "b7138dc53dd5a73257cf4a2eceeb71f0f962333b351e259ffcaeca310853195e",
    },
    Download {
        file: "chm-122130032.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130032.tif",
        sha256: "bc2288fe8edfa268f85550fbfc2a2e53105bd5adeb77ee0db7210650a77b27dc",
    },
    Download {
        file: "chm-122130201.tif",
        url: "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/122130201.tif",
        sha256: "98ffa5f570fe9bfa58fae5ffaa9d54a5aae45cc814d1b2f27219545cf0a67abe",
    },
];

/// True when `<dir>/<file>.ok` records the pinned checksum (downloaded and checked before) and the file is there.
pub fn file_done(dir: &Path, d: &Download) -> bool {
    std::fs::read_to_string(dir.join(format!("{}.ok", d.file))).is_ok_and(|t| t.lines().next() == Some(d.sha256))
        && dir.join(d.file).is_file()
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

/// Every file of `list` into `dir` (curl, so `file://` works too), checked against its pinned SHA-256. Files done before are kept. Returns how many it fetched.
pub fn fetch_files(list: &[Download], dir: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<usize> {
    std::fs::create_dir_all(dir)?;
    let mut n = 0;
    for (k, d) in list.iter().enumerate() {
        check(cancel)?;
        if !file_done(dir, d) {
            let (p, part) = (dir.join(d.file), dir.join(format!("{}.part", d.file)));
            // A file already there (copied in by hand) only needs its check.
            if !(p.is_file() && sha256_file(&p)? == d.sha256) {
                pr.log(&format!("downloading {}", d.file));
                let status = Command::new("curl")
                    .args(["-fsSL", "--retry", "3", "--connect-timeout", "30", "-o"])
                    .arg(&part)
                    .arg(d.url)
                    .status()
                    .context("running curl")?;
                let sum = if status.success() { sha256_file(&part)? } else { String::new() };
                if sum != d.sha256 {
                    let _ = std::fs::remove_file(&part);
                    if status.success() {
                        bail!(
                            "{}: checksum mismatch (got {sum}, pinned {}): the file at {} changed",
                            d.file,
                            d.sha256,
                            d.url
                        );
                    }
                    bail!("{}: download failed (curl {status})", d.file);
                }
                std::fs::rename(&part, &p)?;
                n += 1;
            }
            std::fs::write(dir.join(format!("{}.ok", d.file)), format!("{}\n{}\n", d.sha256, today()))?;
        }
        pr.fraction((k + 1) as f32 / list.len() as f32);
    }
    Ok(n)
}

/// Where ambientCG serves the zips.
pub const AMBIENTCG: &str = "https://ambientcg.com/get?file=";
/// The packed maps' side (texels).
pub const SIDE: u32 = 1024;
/// The packing's version: `material.json` records it, and a material packed by another version is fetched again.
pub const PACK: u32 = 4;

/// The lowercase hex SHA-256 of a file.
pub fn sha256_file(p: &Path) -> Result<String> {
    let mut f = std::fs::File::open(p).with_context(|| format!("{}", p.display()))?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            return Ok(h.finalize().iter().map(|b| format!("{b:02x}")).collect());
        }
        h.update(&buf[..n]);
    }
}

/// True when `<dir>/<id>/material.json` records this material's checksum (fetched and packed before).
pub fn is_done(dir: &Path, m: &Material) -> bool {
    std::fs::read_to_string(dir.join(m.id).join("material.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .is_some_and(|v| v["sha256"] == m.sha256 && v["pack"] == PACK && dir.join(m.id).join("nr.bc3").is_file())
}

/// Every material of `list` into `dir` (fetched from `base`, e.g. [`AMBIENTCG`], with the zip's name appended; curl,
/// so `file://` works too), then `<dir>/<name>.json`. Materials already done are kept. Returns how many it fetched.
pub fn fetch(
    name: &str,
    list: &[Material],
    base: &str,
    dir: &Path,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<usize> {
    std::fs::create_dir_all(dir)?;
    let mut n = 0;
    for (k, m) in list.iter().enumerate() {
        check(cancel)?;
        if !is_done(dir, m) {
            fetch_one(m, base, dir, pr)?;
            n += 1;
        }
        pr.fraction((k + 1) as f32 / list.len() as f32);
    }
    let mats: Vec<_> = list.iter().map(|m| json!({ "id": m.id, "size_m": m.size_m, "used_for": m.used_for })).collect();
    std::fs::write(dir.join(format!("{name}.json")), serde_json::to_string_pretty(&json!({ "materials": mats }))?)?;
    Ok(n)
}

fn fetch_one(m: &Material, base: &str, dir: &Path, pr: &dyn Progress) -> Result<()> {
    let zip_name = format!("{}_2K-JPG.zip", m.id);
    let part = dir.join(format!("{zip_name}.part"));
    pr.log(&format!("{}: downloading {zip_name}", m.id));
    let status = Command::new("curl")
        .args(["-fsSL", "--retry", "2", "--connect-timeout", "20", "-o"])
        .arg(&part)
        .arg(format!("{base}{zip_name}"))
        .status()
        .context("running curl")?;
    let r = (|| -> Result<()> {
        if !status.success() {
            bail!("{}: download failed (curl {status})", m.id);
        }
        let sum = sha256_file(&part)?;
        if sum != m.sha256 {
            bail!("{}: checksum mismatch (got {sum}, pinned {}): the file on ambientCG changed", m.id, m.sha256);
        }
        unpack(m, &part, &dir.join(m.id))
    })();
    let _ = std::fs::remove_file(&part);
    r
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
    let bright = brightness_detail(&image::DynamicImage::ImageRgba8(colour.clone()).to_luma8());
    let albedo = detail_ratio(&colour);
    let mut nr = RgbaImage::new(SIDE, SIDE);
    for (x, y, p) in nr.enumerate_pixels_mut() {
        let n = normal.get_pixel(x, y).0;
        p.0 = [rough.get_pixel(x, y).0[0], n[1], bright.get_pixel(x, y).0[0], n[0]];
    }
    std::fs::write(out.join("albedo.bc1"), compress(&mip_chain(albedo), Format::Bc1, [1.0, 1.0, 1.0]))?;
    // The normal's Y in G weighs most.
    std::fs::write(out.join("nr.bc3"), compress(&mip_chain(nr), Format::Bc3, [0.3, 1.0, 0.5]))?;
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

/// Every level of `levels` compressed as `format` (block weights `w` for R, G, B), concatenated (Godot's
/// `Image.create_from_data` layout for a compressed image with mipmaps).
pub fn compress(levels: &[RgbaImage], format: Format, w: [f32; 3]) -> Vec<u8> {
    let params = Params { algorithm: Algorithm::ClusterFit, weights: w, weigh_colour_by_alpha: false };
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
        assert_eq!(compress(&v, Format::Bc1, [1.0; 3]).len(), 3 * 8);
    }

    #[test]
    fn fetch_checks_the_pinned_checksum() {
        let (d, zp) = fake_zip("sum");
        let sum = sha256_file(&zp).unwrap();
        let base = format!("file://{}/", zp.parent().unwrap().display());
        let out = d.join("out");
        let bad = [Material { id: "Fake001", sha256: "00", size_m: 2.0, used_for: "test" }];
        let e = fetch("test", &bad, &base, &out, &Stdout, &AtomicBool::new(false)).unwrap_err();
        assert!(format!("{e:#}").contains("checksum mismatch"), "{e:#}");
        assert!(!out.join("Fake001/material.json").exists() && !out.join("Fake001_2K-JPG.zip.part").exists());

        let sum: &'static str = Box::leak(sum.into_boxed_str());
        let good = [Material { id: "Fake001", sha256: sum, size_m: 2.0, used_for: "test" }];
        assert_eq!(fetch("test", &good, &base, &out, &Stdout, &AtomicBool::new(false)).unwrap(), 1);
        let nr = std::fs::read(out.join("Fake001/nr.bc3")).unwrap();
        assert_eq!(nr.len(), (0..=10).map(|k| 16 * ((SIDE as usize >> k).div_ceil(4)).pow(2)).sum::<usize>());
        assert!(out.join("Fake001/Fake001_2K-JPG_Color.jpg").is_file() && out.join("test.json").is_file());
        // Done before: kept, nothing fetched (the source may be gone).
        std::fs::remove_file(&zp).unwrap();
        assert_eq!(fetch("test", &good, &base, &out, &Stdout, &AtomicBool::new(false)).unwrap(), 0);
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn fetch_files_checks_and_keeps() {
        let (d, zp) = fake_zip("files");
        let url: &'static str = Box::leak(format!("file://{}", zp.display()).into_boxed_str());
        let sum: &'static str = Box::leak(sha256_file(&zp).unwrap().into_boxed_str());
        let out = d.join("out");
        let no = AtomicBool::new(false);
        let bad = [Download { file: "a.zip", url, sha256: "00" }];
        assert!(format!("{:#}", fetch_files(&bad, &out, &Stdout, &no).unwrap_err()).contains("checksum mismatch"));
        assert!(!out.join("a.zip").exists() && !out.join("a.zip.part").exists());
        let good = [Download { file: "a.zip", url, sha256: sum }];
        assert_eq!(fetch_files(&good, &out, &Stdout, &no).unwrap(), 1);
        assert!(file_done(&out, &good[0]) && file_date(&out, &good[0]).is_some_and(|d| d.len() == 10));
        assert_eq!(fetch_files(&good, &out, &Stdout, &no).unwrap(), 0, "kept");
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
        let mut files: Vec<_> = SCENERY.iter().map(|d| d.file).collect();
        files.sort();
        files.dedup();
        assert_eq!(files.len(), SCENERY.len(), "a scenery file twice");
        for d in SCENERY {
            assert!(d.sha256.len() == 64 && d.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "{}", d.file);
            assert!(d.url.starts_with("https://") && !d.file.contains('/'), "{}", d.file);
        }
        for m in LISTS.iter().flat_map(|(_, l)| l.iter()) {
            assert!(m.sha256.len() == 64 && m.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "{}", m.id);
            assert!(m.size_m >= 0.25 && m.size_m < 10.0, "{}", m.id);
        }
    }
}
