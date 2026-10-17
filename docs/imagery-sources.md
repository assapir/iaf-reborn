# High-resolution imagery sources — licence survey

This survey finds the **sharpest imagery we may legally use** over the game's theatre. Key results: the Survey of
Israel's open 2 m aerial orthophoto covers Israel, and the CNES SPOT 5 archive (5 m, open licence) covers the rest. All
commercial basemaps (Google, Bing, Esri and others) are ruled out by their terms. The full ranking is in §1, the
recommendation in §5.

It follows up docs/imagery-research.md, which picked ESA (European Space Agency) WorldCover / Sentinel-2 at 10 m as the
base. The rules for a usable source:

- **Theatre**: Israel, Sinai / Egypt incl. the Nile delta and Suez, Jordan, Lebanon, Syria, western Iraq, Cyprus.
- **Project**: an open-source game under the GPL (GNU General Public License).
- **Delivery**: the game **downloads / converts it on the user's machine at setup (or streams it), never redistributes
  it**.
- **Access**: no "bring your own API key" step.

Status: research only, no code. Built since: the Survey of Israel 2 m layers (docs/imagery.md §8). SPOT 5 not started.
Checked 2026-10-01. The clauses are quoted from the providers' own pages (links inline). This is not legal advice;
where a clause is ambiguous, the text says so.

Our levels for reference (docs/imagery-research.md §3): L0 1.24 m, L1 2.5 m, L2 5.0 m, L3 9.9 m,
L4 19.9 m, L5 39.7 m, L6 79.4 m per pixel. The original has L0..L2 only at ~20 airbase/target insets.

Check sites used below:

- Ramat David (32.665 N 35.179 E)
- Tel Nof (31.839 N 34.822 E)
- Ramon (30.776 N 34.667 E)
- Rishon LeZion (31.96 N 34.80 E)
- Cairo West (30.116 N 30.915 E)
- Damascus / Mezze (33.477 N 36.223 E)
- Paphos (34.718 N 32.486 E)

## 1. Result in one table

Abbreviations in the table: res. = ground resolution; pan = panchromatic (one black-and-white band); B&W = black and
white; COG = Cloud Optimized GeoTIFF; WMTS = Web Map Tile Service; STAC = SpatioTemporal Asset Catalog (a search API for
scenes); WAF = web application firewall; RPC = rational polynomial coefficients (a sensor model for orthorectifying);
NC = non-commercial; OAM = OpenAerialMap; DLS = Cyprus Department of Lands and Surveys; S2 = Sentinel-2.

| rank | source | res. | where | dates | licence (short) | access | verdict |
|---|---|---|---|---|---|---|---|
| 1 | **Survey of Israel aerial orthophoto "2015, 2 m"** on data.gov.il | **2 m** colour | all Israel + West Bank + Golan (79 map sheets) | 2015 | **data.gov.il open licence**: copy, distribute, derive, commercial OK, credit the source | direct ZIP per sheet (no account); AWS-WAF bot challenge | **use — best legal high-res for Israel** |
| 2 | ESA WorldCover S2 composite / EOX S2 cloudless 2016–17 | 10 m colour | whole theatre | 2016–2021 | CC BY 4.0 | AWS COGs / WMTS | keep as base (as already planned) |
| 3 | **CNES SPOT World Heritage** (SPOT 1–5 archive) | **5 m pan** (SPOT 5; 2.5 m "THR" pairs exist), 10 m pan SPOT 1–4, 10/20 m colour | whole theatre (1 810 SPOT 5 scenes touch Ramat David, 374 Cairo, 364 Damascus, 135 one Sinai point) | 1986–2015 (incl. **1997–98**) | **Etalab Open Licence 2.0** (≈ CC BY) | GEODES STAC API, free CNES account (a free login; no paid key); raw L1A — we orthorectify | **use for the rest of the theatre** (5 m modern-ish, or 10 m period-correct 1998) |
| 4 | **Declassified CORONA KH-4B** (USGS Declass 1) / CAST "CORONA Atlas" | **~1.8 m** B&W | very heavy Middle East coverage | 1967–72 | **public domain** (USGS); CAST's orthorectification aids CC BY-SA 4.0 | EarthExplorer (free account; $30/frame to scan unscanned film); CAST atlas download with RPCs | **use as an optional "historical" look** |
| 5 | Declassified KH-7 GAMBIT (Declass 2) | 0.6–1.2 m B&W | targeted frames only | 1963–67 | public domain | EarthExplorer | spot patches, if frames exist over our bases |
| 6 | Declassified KH-9 mapping camera (Declass 2) / KH-9 panoramic (Declass 3) | 6–9 m / 0.6–1.2 m B&W | mapping camera global; panoramic at USGS "primarily over the United States, Antarctica, and the Arctic Circle" | 1971–84 | public domain | EarthExplorer | mapping camera: meh; panoramic: probably no theatre frames at EROS |
| 7 | Cyprus Dept. of Lands and Surveys orthophotos (1963, 1993, 2014 10 cm, 2019) | ≤ 0.5 m | Cyprus (2019 covers the whole island) | 1963–2019 | INSPIRE metadata says "open licence"; OSM's JOSM list says "unclear license" | ArcGIS MapServer tiles (tile export disabled) | **ask DLS first**; then a nice Cyprus patch |
| 8 | Sentinel-2 super-resolution (ESA OpenSR **SEN2SR**) | 2.5 m (synthesised) | anywhere S2 is | any S2 date | code CC0; outputs = derived Copernicus data | run locally (GPU) | **an option only, not a recommendation** (it is learned upscaling) |
| 9 | Landsat 7 / 8 / 9 pan-sharpened | 15 m | whole theatre | 1999– | public domain | AWS / Planetary Computer / EarthExplorer | coarser than S2; only for a 1999 look |
| 10 | Maxar(Vantor) Open Data / OpenAerialMap | 0.3–0.8 m (sat), 2–10 cm (drones) | Beirut 2020; Hatay / Afrin / Azaz 2023; tiny drone patches in Israel | event dates | CC BY-NC 4.0 (Maxar), CC BY / BY-SA / BY-NC (OAM) | AWS / OAM API | not useful (wrong places, NC) |
| ✗ | Google Map Tiles (2D satellite, Photorealistic 3D), Bing / Azure Maps, Mapbox Satellite, Esri World Imagery + Wayback, Apple, Yandex, HERE, MapTiler | 0.15–1 m | everywhere | current | proprietary; bulk download, offline use and derivatives forbidden, key required | — | **not usable** (details §3) |
| ✗ | Copernicus Contributing Missions VHR (VHR2021/2024 mosaics) | 2–4 m | Europe (EEA39) incl. Cyprus | 2021, 2024 | eligible institutional users only; mosaic "only available as a web map service (WMS), and not for data download" | — | not usable |
| ✗ | Planet NICFI | 4.77 m | tropical forest belt only | 2015–2025 | non-commercial; program ended Jan 2025 | — | no coverage |
| ✗ | Satellogic EarthView, ALOS PRISM, Airbus OneAtlas / Pléiades, ESA third-party missions | 1–2.5 m | scattered chips / research-only / paid | — | gated or research-only | — | not usable |

**Recommendation (§5):**

- **Israel**: 2 m from the Survey of Israel open orthophoto (→ our L1/L2 everywhere in Israel).
- **Sinai / delta / Suez / Jordan / Lebanon / Syria / Iraq**: SPOT 5 pan-sharpened at 5 m (→ L2/L3).
- **Everywhere**: WorldCover 10 m as the seamless fallback and colour reference.
- **Opt-in "historical" layer**: CORONA KH-4B (1.8 m B&W) near selected bases.
- **Period-correct "1998" variant**: SPOT 2/4 (10 m pan, 1997–98) from the same SWH archive.

## 2. Open and government sources (detail)

This section gives, per source, what it is, its resolution, coverage, licence (quoted), access and the work it needs.

### 2.1 Survey of Israel (MAPI) 2015 aerial orthophoto, 2 m — data.gov.il  ★ best find

Key fact: a 2 m colour orthophoto of all Israel under an open, CC BY-like licence. The site's bot challenge makes the
download a manual browser step.

- **What**: the organisation "המרכז למיפוי ישראל" (Survey of Israel) publishes 79 datasets titled
  "תצלום אויר 2015 2 מטר - גליון <name>" ("aerial photo 2015, 2 m — sheet <name>"), one ZIP per 1:50 000 map sheet.
  - Found via the API of CKAN (the portal's data-catalogue software):
    `https://data.gov.il/api/3/action/package_search?q=תצלום&rows=200`.
  - Sheets include שפרעם / נצרת (Ramat David), גדרה / רחובות בנגב / ראשון לציון (Tel Nof, Rishon LeZion), מצפה רמון /
    הר ארדון / הר לוץ (Ramon), תל אביב, חיפה, באר שבע, אילת, מרום גולן, עין זיון, רמאללה, שכם, יריחו … i.e. **all of
    Israel, the West Bank and the Golan**.
  - Published 2017-11-01, metadata updated 2023-03-21.
- **Resolution**: 2 m, colour aerial photography (2015). That is finer than our L1 (2.5 m): the whole of Israel could
  get L1-level imagery; today only ~20 insets have it.
- **Licence**: the dataset carries no licence of its own, so the portal's default applies. Quoted from the data.gov.il
  terms of use ([data.gov.il/he/terms-of-use](https://data.gov.il/he/terms-of-use), read via a text proxy because the
  site sits behind a bot challenge):
  > "השימוש במאגרי המידע … אינו כפוף לתנאי השימוש, אלא לרישיון השימוש המובא להלן. ככל שלמאגר מידע מוצמד רישיון
  > שימוש השונה מהרישיון המובא להלן, יגבר הרישיון המוצמד"
  > (use of the datasets is governed by the licence below, unless a dataset carries its own licence)
  >
  > "רישיון זה מעניק לך רישיון עולמי, ללא תמלוגים, בלתי מוגבל בזמן ולא בלעדי לשימוש במידע"
  > (a worldwide, royalty-free, perpetual, non-exclusive licence)
  >
  > **"אתה רשאי להעתיק את המידע, להפיץ אותו, להעמיד אותו לרשות לציבור, לשדר אותו, לבצע שינויים טכניים במידע וליצור
  > ממנו יצירות נגזרות בכל מדיום או פורמט. אתה רשאי לעשות שימוש במידע באופן מסחרי ובאופן שאינו מסחרי."**
  > (you may copy, distribute, make available to the public, transmit, technically modify and create derivative works
  > in any medium or format; commercial and non-commercial use allowed)
  >
  > "בשימוש במידע, עליך לציין את מקור המידע." (you must credit the source)
  >
  > Forbidden: misleading / distorting presentation, unlawful use, privacy harm, implying access to identified data.

  What this means for us:
  - It is effectively CC BY. A GPL game may ship a downloader, and the user may convert the data. We could even host
    the converted nodes (we still won't).
  - Attribution: "Contains aerial photography © Survey of Israel 2015, via data.gov.il".
  - The licence text says changes apply from posting, and the version in force at download time governs. So the setup
    tool should record the download date.
- **Access**: direct, unauthenticated URLs, e.g.
  `https://data.gov.il/dataset/dc0b20a2-…/resource/0d1f45b4-…/download/bqt.zip`.
  - Sizes measured by range request: bqt 249 MB, hzf 240 MB, hmr 201 MB, bsh 328 MB → **~79 × ~250 MB ≈ 20 GB** for
    the country (estimate).
  - The site is behind CloudFront + AWS WAF. The first few `curl` range requests returned 206; after that every
    request got **HTTP 202 with a JavaScript challenge** (also for the HTML pages; the CKAN `/api/3/` JSON stayed
    open). So a scripted bulk download is unreliable.
  - The setup step should therefore: (1) list the 79 links (from the CKAN API); (2) let the user download them in a
    browser into a folder (or retry slowly); (3) convert.
  - Internal format (GeoTIFF / ECW / JPEG2000, ITM grid — Israeli Transverse Mercator) is not yet confirmed: the ZIP
    central directory could not be read once the challenge kicked in. Check one sheet by hand before writing the
    converter.
- **Caveats**:
  - The photos are from 2015, newer than the game's 1998: towns, roads and airbase shelters differ. See the "original
    wins" rule in imagery-research.md §4.1.
  - data.gov.il has this 2015 set only. Searched: "אורתופוטו", "orthophoto", "תצלום", and the whole Survey of Israel
    organisation.
  - The newer govmap orthophotos (≈ 25–50 cm) remain "© State of Israel, use needs the Survey director's permission"
    (imagery-research.md §3). We could ask for them, but a 2 m pack works without them.

### 2.2 CNES SPOT World Heritage (SWH) — SPOT 1–5, 1986–2015

Key fact: open-licence (Etalab 2.0) SPOT scenes cover the whole theatre, many times over, including 1997–98. They come
raw, so we must orthorectify them ourselves.

- **What / resolution**: the whole SPOT 1–5 archive.
  - SPOT 1–4: 10 m pan, 20 m multispectral.
  - SPOT 5: 5 m pan, 10 m colour, plus "THR" mode, where two 5 m pan scenes are combined to 2.5 m. The STAC items list
    `coupled_scenes_thr`, i.e. the pairs exist; the 2.5 m product itself is not distributed.
  - Scenes are 60 × 60 km.
- **Coverage**: GEODES STAC search (`https://geodes-portal.cnes.fr/api/stac/search`, no auth for search) returns, per
  point (Ramat David / Cairo / Damascus / a Sinai point):
  - SPOT 5 L1A: 1 810 / 374 / 364 / 135.
  - SPOT 4: 664 / 451 / 235 / 270.
  - SPOT 1–3: 469 / 251 / 179 / 148.

  Sample: `S5 HRG-1 2006-08-21`, 5 % cloud, covering Haifa–Jezreel (quicklook kept in the scratchpad). So **every part
  of the theatre has many scenes**, including 1997–98 SPOT 2/4 for a period-correct look.
- **Licence**:
  - GEODES: "la licence ETALAB Ouverte 2.0", requiring only a CNES credit
    ([geodes.cnes.fr — Les images SPOT scintillent dans Geodes](https://geodes.cnes.fr/les-images-spot-scintillent-dans-geodes/)).
  - SWH since June 2021: "simply create an account and agree to the terms of the ETALAB 2.0 licence"
    ([cartonumerique](https://cartonumerique.blogspot.com/2021/06/spot.html), [CNES SWH](https://regards.cnes.fr/html/swh/Home-swh3.html)).
  - Etalab 2.0 allows reuse, modification, commercial use and redistribution with attribution ("© CNES <year>,
    distribution SWH / Airbus DS" style credit). Fine for a GPL project and a user-side downloader.
- **Access**: a free CNES/GEODES account gives an API key; the download endpoint returns an error without it. This is a
  *free account*, with no payment or metering. Is that acceptable? Open question for the user; the alternative is the
  user logging in once at setup.
- **Effort**: the archive is **L1A (raw, no geometric correction)**. The L1C (orthorectified) SWH collections exist in
  GEODES (`THEIA_SWH-PHASE1_SPOT*_L1C`) but returned **0 items** over our points (France-centric so far). Our own
  pipeline would be:
  1. Orthorectify: SPOT DIMAP metadata + Copernicus GLO-30 DEM (digital elevation model) with Orfeo ToolBox (OTB;
     `otbcli_OrthoRectification`, supports SPOT 5), or GDAL with GCPs (ground control points).
  2. Pan-sharpen 5 m pan + 10 m colour (`gdal_pansharpen.py`).
  3. Colour-match to WorldCover.

  Scene choice per area (cloud, season, sun) is manual-ish. Size: ~60 × 60 km per scene, 12 000² pan; theatre land
  ≈ 600 000 km² → ~170–250 scenes per pass, **roughly 20–40 GB** download (estimate).
- **Quality**: 5 m pan is 2× sharper than Sentinel-2, and the content is 2015 or older (closer to 1998). Radiometry is
  older (8-bit, some striping). Colour from the 10 m MX (multispectral) bands after pan-sharpening is decent.

### 2.3 Declassified US reconnaissance imagery (USGS EROS) — the "period" look

Key fact: public-domain film from 1960–84 (USGS EROS = Earth Resources Observation and Science center). CORONA KH-4B
reaches 1.8 m over the Middle East; georeferencing it takes real work.

| set | system | years | ground res. | theatre | notes |
|---|---|---|---|---|---|
| Declass 1 (1996) | CORONA KH-1…KH-4B, ARGON, LANYARD | 1960–72 | KH-4B "6 feet" (1.8 m), KH-6 "6 feet" | **excellent** (CORONA is the standard archive for Middle East landscape archaeology) | panoramic film, stereo pairs |
| Declass 2 (2002) | KH-7 GAMBIT, KH-9 mapping camera | 1963–67 / 1973–80 | KH-7 "2 to 4 feet" (0.6–1.2 m); KH-9 MC "20-30 feet" | KH-7 targeted (military sites — possibly our bases); KH-9 MC broad | |
| Declass 3 (2011–13) | KH-9 HEXAGON panoramic | 1971–84 | "2-4 feet" | EROS subset "primarily over the United States, Antarctica, and the Arctic Circle" ([data.gov](https://catalog.data.gov/dataset/declass-3-2013-usgs-subset-of-hexagon-missions-kh-9-1971-1984)) | rest of the film at NARA (US National Archives) |

(MC = mapping camera.)

- **Licence**: USGS says "Data are **Public Domain**" (Declass 2 page) and, for Declass 3, "Imagery is public domain"
  ([Declass 1](https://www.usgs.gov/centers/eros/science/usgs-eros-archive-declassified-data-declassified-satellite-imagery-1),
  [Declass 2](https://www.usgs.gov/centers/eros/science/usgs-eros-archive-declassified-data-declassified-satellite-imagery-2),
  [Declass 3](https://www.usgs.gov/centers/eros/science/usgs-eros-archive-declassified-data-declassified-satellite-imagery-3)).
  Any use is allowed; credit "USGS EROS".
- **Access / cost**:
  - EarthExplorer needs a free USGS login.
  - Already-scanned frames download free at 7 µm (3 600 dpi) or 14 µm TIFF, 188 MB–1 GB per file.
  - Unscanned frames cost "$30.00 per frame" for an on-demand scan.
  - The machine-to-machine API needs an approved account.
  - Images "have not been georeferenced".
- **CAST CORONA Atlas** ([corona.cast.uark.edu](https://corona.cast.uark.edu/), Univ. of Arkansas):
  - Middle East focused: 279 missions / 2 214 KH-4B images.
  - Downloadable NITF **with RPC sensor models**, so GDAL can orthorectify with a DEM.
  - "licensed under CC BY-SA 4.0", credit "Center for Advanced Spatial Technologies, University of Arkansas/U.S.
    Geological Survey"; the site also says access is "for non-commercial use".
  - The CAST RPCs are the cheap way to get CORONA onto the map. The underlying pixels are public domain either way.
- **Fit**: sub-2 m black-and-white with film grain, from 1967–72 (Sinai under Israeli control, pre-1973 airfields).
  That is an earlier world than 1998, and a striking optional "historical recon" look for a few airbases / targets.
  Panoramic distortion and stereo convergence make georeferencing real work (RPCs or many GCPs per frame). It suits
  local patches only; it is not a theatre-wide layer.

### 2.4 Cyprus — Department of Lands and Surveys

Key fact: sharp orthophotos (incl. 1993) exist, but the licence is unclear; ask DLS before use.

- **Services**: ArcGIS services at `https://eservices.dls.moi.gov.cy/arcgis/rest/services/BASEMAPS` list:
  - `Imagery_Orthophoto_1963`
  - `Imagery_Orthophoto_1993` (period!)
  - `Imagery_Orthophoto_2014_10cm`
  - `Imagery_Satellite_2009_2013`
  - `Orthoimagery_2019_WebMercator` (tiled, 22 LODs — levels of detail; the extent covers the whole island)

  A z16 sample at Paphos airport loads fine. `exportTilesAllowed: false`.
- **Licence**: the INSPIRE geoportal record (the EU spatial-data catalogue) lists the use limitation
  "Ανοικτής Άδειας Χρήσης" (open licence) and no access restrictions. But JOSM (an OpenStreetMap editor) removed the
  layer in 2020 as "unclear license + server does not work"
  ([JOSM Maps/Cyprus](https://josm.openstreetmap.de/wiki/Maps/Cyprus)).
- **Action**: **Ask DLS** (one e-mail) before using. Cyprus is a small, mostly-sea part of the theatre anyway.

### 2.5 Sentinel-2 super-resolution (flagged option, not a recommendation)

Key fact: a model synthesises 2.5 m from 10 m Sentinel-2. The detail is learned, so it is listed as an experiment only.

- **ESA OpenSR / SEN2SR** ([github.com/ESAOpenSR/SEN2SR](https://github.com/ESAOpenSR/SEN2SR), code **CC0-1.0**;
  the diffusion model repo `opensr-model` has a custom licence): "super-resolve Sentinel-2 satellite imagery up to 2.5
  meters", designed for radiometric consistency with the 10 m input. The output is derived Copernicus data (free,
  credit "Contains modified Copernicus Sentinel data").
- **Why only an experiment**:
  - It is learned upscaling: plausible edges, sometimes invented detail (roads / field borders), especially in the
    diffusion variant.
  - The user dislikes AI upscaling of *art*. So it is listed only for areas where real imagery stops at 10 m (e.g.
    western Iraq, Jordan desert). The SPOT 5 real 5 m data covers those, so SR (super-resolution) is probably
    unnecessary.
  - It needs a GPU. Theatre-wide at 2.5 m is ~100 Gpx (gigapixels), so it would run only near airbases, if at all.
- Commercial SR (Gamma Earth S2DR3 1 m) is paid and closed: not considered.

### 2.6 Others checked

These sources were checked and rejected (or add nothing over the ones above):

- **Landsat 7 ETM+ / 8 / 9 pan**: 15 m, public domain (USGS). Landsat 7 1999–2003 is the closest "late 90s" colour
  source. It is coarser than Sentinel-2.
- **Maxar (now Vantor) Open Data Program**: "licensed under the Creative Commons Attribution Non-Commercial 4.0"
  ([AWS registry](https://registry.opendata.aws/maxar-open-data/)); events only. On OpenAerialMap over our bbox
  (bounding box):
  - Beirut port explosion 2020 strips (0.4–0.8 m; one strip reaches 32.4 N along 35.4–35.6 E).
  - Turkey–Syria earthquake 2023 (Hatay, Afrin, Azaz, 0.3 m) at the theatre's northern edge.

  Non-commercial is OK for a free game but incompatible with redistribution under the GPL. The places are wrong for us
  anyway.
- **OpenAerialMap** (`api.openaerialmap.org/meta?bbox=29.7,27.0,38.3,36.7` → 83 items): drone patches of a few
  hectares (Weizmann Institute, Yatir forest, Nahariya, Kfar Ruppin, Douma…), CC BY / BY-SA / BY-NC. Useless as a layer.
- **Planet NICFI**: "tropical forested regions between 30 degrees North and 30 degrees South", non-commercial, contract
  ended 2025-01 ([Planet NICFI FAQ](https://assets.planet.com/docs/NICFI_General_FAQs.pdf)). No coverage.
- **Copernicus Contributing Missions VHR (very high resolution)**: Europe only, for institutions; the public has no
  access.
  - VHR2021 mosaic: "only available as a web map service (WMS), and not for data download"
    ([CLMS](https://land.copernicus.eu/en/products/european-image-mosaic/very-high-resolution-image-mosaic-2021-true-colour-2m)).
  - VHR2024: for "Copernicus Services and Union Institutional Users, National Public Authorities, Union Research
    Projects, and International Organisations" ([CDSE](https://dataspace.copernicus.eu/node/4048)).
- **Satellogic EarthView**: CC BY 4.0, 1 m, but ~3 M scattered 384 m chips for ML (machine learning) training, gated on
  Hugging Face. Rejected.
- **ALOS PRISM 2.5 m**: closed (ESA third-party / commercial). JAXA's open AVNIR-2 ORI (orthorectified product) is 10 m,
  so it adds nothing.
- **Airbus OneAtlas, Pléiades, SPOT 6/7, ESA TPM (Third Party Missions)**: paid or research-proposal only.
- **USGS high-res orthoimagery / NAIP**: US only.
- Egypt, Jordan, Lebanon, Syria and Iraq: no open orthophoto programme found.

## 3. Commercial basemaps — why not

Every commercial basemap below forbids what we need. Common to all:

- An API key/token is required: either ours (embedded in a public GPL client and billed to us) or the user's
  (rejected).
- Caching is allowed only as a transient HTTP cache.
- Bulk download and derivative imagery are forbidden.

Our use (warp into the game frame, colour-match, blend with the 1998 photos, keep on disk) breaks each of these terms.

- **Google Maps Platform** (Map Tiles API: 2D satellite, Photorealistic 3D Tiles). [Terms §3.2.3](https://cloud.google.com/maps-platform/terms):
  > "(a) No Scraping. Customer will not export, extract, or otherwise scrape Google Maps Content for use outside the
  > Services. For example, Customer will not: (i) pre-fetch, index, store, reshare, or rehost Google Maps Content
  > outside the services; (ii) bulk download Google Maps tiles …"
  > "(b) No Caching. Customer will not cache Google Maps Content except as expressly permitted under the Maps Service
  > Specific Terms." (the [Service Specific Terms](https://cloud.google.com/maps-platform/terms/maps-service-terms) grant no
  > tile caching)
  > "(c) No Creating Content From Google Maps Content …"
  > "(e) No Use With Non-Google Maps. … Customer will not use the Google Maps Core Services with or near a non-Google
  > Map in a Customer Application."

  [Map Tiles API policies](https://developers.google.com/maps/documentation/tile/policies): "you must not pre-fetch,
  index, store, or cache any Content … You may not use Map Tiles API for any non-visualization use cases, such as: …
  Offline uses", and you must respect `Cache-Control`.

  Third-party renderers (Cesium etc.) are allowed for 3D Tiles with Google logo + attribution, and you "may overlay
  your own 3D objects on Photorealistic 3D Tiles". So *live streaming* of 3D Tiles into a Godot renderer is
  conceptually allowed, but only:
  - with a billed Google key;
  - with no disk cache beyond HTTP rules;
  - with Google branding on screen;
  - kept apart from our own (non-Google) 1998 map ((e)).

  Not compatible with this project.
- **Bing Maps / Azure Maps**: Bing Maps for Enterprise free (Basic) accounts ended 2025-06-30, and Enterprise ends
  2028-06-30. The successor is Azure Maps (`microsoft.imagery` tiles).
  [Microsoft Product Terms — Azure Maps](https://www.microsoft.com/licensing/terms/productoffering/MicrosoftAzure/MCA):
  - "Customer may not cache or store results delivered by the Azure Maps API for the purpose of scaling such Results …
    to serve multiple users, or to circumvent any functionality … including … map data tiles"
  - "Customer will not modify or create a derivative work based on Azure Maps"
  - "Customer may not, nor may permit end users to, replace maps from Azure Maps with maps supplied by any other
    mapping platform"
  - and notably "When using content licensed under or subject to an open-source license, Customer may not combine the
    use of Azure Maps … in a way that potentially compromises copyright protection."

  Rejected.
- **Mapbox Satellite**: [Product Terms (2026-07)](https://www.mapbox.com/legal/product-terms):
  - §1.9 "not scrape or systematically download Licensed Map Content … (v) not export, download, cache or store
    Licensed Map Content".
  - §2.8.1 allows an on-device cache, but "limited to thirty (30) days on the same device" and populated directly from
    the API.
  - §2.8.2 "Customer shall not use Mapbox's satellite and/or aerial imagery to improve the accuracy of or otherwise
    enhance any imagery".
  - §1.6 forbids tracing / deriving.

  The only legal shape would be streaming with a 30-day cache, with our token and our bill. Blending it into the 1998
  photos is arguably "enhancing imagery". Rejected.
- **Esri World Imagery (and World Imagery Wayback)**: item licence
  ([ArcGIS item](https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9)):
  "This work is licensed under the Esri Master License Agreement … Export: This layer is not intended to be used to
  export tiles for offline. If you would like to export imagery for offline use in ArcGIS applications, you may use
  the World Imagery (for Export) layer". That layer is for "offline use in ArcGIS applications and other applications
  built with an ArcGIS Runtime SDK", max 150 000 tiles per request. Wayback export follows the same rule.
  - Content: Vantor (ex-Maxar) Vivid 0.3–1.2 m, dates 2021–2025 at our sites (identify: Ramat David 2024-10-26, Tel Nof
    2024-12-24, Ramon 2021-02-22, Cairo West 2025-05-07, Mezze 2025-05-31).
  - The quality is what we'd want (a z16 sample at Ramat David clearly shows taxiways, hangars, buildings), but the
    terms rule it out.
  - Also: it is the godotiles default provider, see imagery-research.md §2.
- **Apple MapKit / MapKit JS**: Map Data "may not be cached, pre-fetched, or stored … other than on a temporary and
  limited basis solely as necessary for your use of the Apple Maps Service"; Apple platforms / web only. Rejected.
- **Yandex Maps API**: free tier "You may not store the data you receive from the API"
  ([terms of free use](https://yandex.com/dev/commercial/doc/)); for web/apps open to all; logo always visible.
  Rejected.
- **HERE**: "Satellite Imagery is made available for online use and viewing only and may not be downloaded or
  otherwise extracted for offline use in any capacity" ([HERE general content supplier terms](https://legal.here.com/terms/general-content-supplier/terms-and-notices/)).
  Rejected.
- **MapTiler Satellite**: [terms](https://www.maptiler.com/terms/): "You may not resell or redistribute … our Products",
  "you may not produce commercial derivative works … to improve the accuracy of other satellite imagery", and
  "It is expressly prohibited to manipulate or modify map content, in the form of vectors, pixels or underlying
  metadata". Warping / colour-matching is modifying pixels. Rejected.

Side note — Israel resolution: until 2020 the US Kyl–Bingaman Amendment capped US-sourced imagery of Israel at 2 m.
NOAA moved the cap to 0.4 m in June 2020. That is why commercial basemaps of Israel only became sharp after 2020, and
why a 2 m national orthophoto was "the best public" for years.

## 4. Quality / size comparison at our levels

The table shows, per source, the finest game level it can feed and the download / disk cost (WB = West Bank,
Gpx = gigapixels).

| source | native | best game level it can feed | theatre part | download | on disk (converted) |
|---|---|---|---|---|---|
| Survey of Israel 2015 | 2 m | **L1 (2.5 m)** | Israel, WB, Golan (~28 000 km²) | ~20 GB (79 ZIPs) | L1 ≈ 4.5 Gpx → ~1.2–1.5 GB JPEG nodes, + L2/L3 ≈ 0.4 GB |
| SPOT 5 pan-sharpened | 5 m | **L2 (5 m)** / L3 | rest of the land (~600 000 km²) | ~20–40 GB (est., per pass) | L3 everywhere ≈ 2.5 GB; L2 everywhere ≈ 10 GB (or L2 only within ~30 km of bases) |
| SPOT 2/4 (1997–98) | 10 m pan / 20 m colour | L3 | whole theatre | ~20 GB | ~2.5 GB |
| WorldCover / EOX | 10 m | L3 | whole theatre | 11–43 GB (COG ranges) | 0.8–3 GB |
| CORONA KH-4B | ~1.8 m B&W | L1 | selected bases | ~0.3–1 GB per frame | small (patches) |

The original's L4 (19.9 m) over Israel is already sharp. The visible wins:

- Survey of Israel set: **L3→L1 everywhere in Israel** (low-level flying between bases).
- SPOT 5: **L6 (79 m) → L2/L3** over Sinai, Egypt, Jordan, Syria.

## 5. Recommendation

Use these sources, in this order of priority:

1. **Israel (incl. West Bank, Golan): Survey of Israel 2015 2 m** (open licence, credit "© Survey of Israel").
   1. Setup lists the 79 sheet URLs from the CKAN API.
   2. The user downloads them (in a browser, because of the WAF challenge) into `assets/source/imagery/mapi2015/`.
   3. `iaf-terrain imagery` converts them through the georeference warp into L1..L3 nodes.

   Original L0..L2 insets still win by default (they match the 1998 airbases); a sub-option may let the 2 m data
   replace them.
2. **Rest of the theatre: SPOT 5 (SWH, Etalab 2.0), 5 m pan + 10 m colour, pan-sharpened**: the best low-cloud scene
   per area, 2003–2012, orthorectified with OTB/GDAL + GLO-30, colour-matched to WorldCover. Needs a free CNES account
   (open question: acceptable as a one-time setup login?). Feeds L2 near bases / targets, L3 elsewhere.
3. **Fallback / colour reference everywhere: WorldCover S2 10 m** (as already planned). It fills gaps (clouds, missing
   SPOT scenes) and is the colour target for both packs.
4. **Optional "Historical recon" layer: CORONA KH-4B 1967–72** (public domain; CAST RPCs), B&W, over a handful of
   airbases and targets. Cheap to try on one base (Ramat David or an Egyptian base) before committing.
5. **Optional "1998" variant**: SPOT 2/4 1997–98 at 10 m from the same SWH pipeline (period-correct towns).
6. **Rejected**: Google / Bing / Azure / Mapbox / Esri / Apple / Yandex / HERE / MapTiler (terms), CCM (Copernicus
   Contributing Missions) VHR (eligibility), NICFI (coverage), Maxar open data (places, NC). **Maybe later**: Cyprus
   DLS 2019 after an e-mail confirming the licence; SEN2SR only as an experiment.

Open questions for the user:

- (a) Free-account downloads (CNES GEODES, USGS EarthExplorer): OK as a one-time setup step, or manual-download only?
- (b) Should the 2015 Israeli 2 m imagery replace the original insets, or only fill around them?
- (c) Is it worth an e-mail to Cyprus DLS (licence) and to the Survey of Israel (newer orthophoto for a free
  non-commercial game)?
- (d) Which default outside Israel: SPOT 5 "modern-ish 5 m" or SPOT 2/4 "1998 10 m"?

Scratchpad samples (not committed): Esri z13/z16 at the five sites (comparison only), EOX 2017 z13, Cyprus 2019 z16/z18,
SPOT 5 2006 quicklook over Haifa–Jezreel.
