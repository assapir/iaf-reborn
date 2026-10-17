# Re-encode every image of a glb as KTX2 / Basis Universal (KHR_texture_basisu) with mipmaps, using the `basisu` CLI
# (brew install basis_universal). Normal maps (images used as a material's normalTexture) get UASTC (high quality),
# the rest ETC1S unless `uastc_all`; occlusion / roughness / metallic maps are encoded as linear data. Godot 4.7's runtime GLTFDocument reads them (decoded to RGBA8 on load).
#
#   python3 tools/plane/glb_ktx2.py in.glb out.glb
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile


def read_glb(path):
    data = open(path, "rb").read()
    assert data[:4] == b"glTF"
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    blen = struct.unpack_from("<I", data, 20 + jlen)[0]
    return doc, bytearray(data[28 + jlen:28 + jlen + blen])


def write_glb(path, doc, chunks):
    """chunks: [bytes per bufferView] -> one packed BIN, bufferViews rewritten in order."""
    blob = bytearray()
    for view, raw in zip(doc["bufferViews"], chunks):
        while len(blob) % 4:
            blob += b"\0"
        view["byteOffset"] = len(blob)
        view["byteLength"] = len(raw)
        view["buffer"] = 0
        blob += raw
    while len(blob) % 4:
        blob += b"\0"
    doc["buffers"] = [{"byteLength": len(blob)}]
    j = json.dumps(doc, separators=(",", ":")).encode()
    while len(j) % 4:
        j += b" "
    out = b"glTF" + struct.pack("<II", 2, 28 + len(j) + len(blob)) + struct.pack("<I", len(j)) + b"JSON" + j
    out += struct.pack("<I", len(blob)) + b"BIN\0" + bytes(blob)
    open(path, "wb").write(out)


def convert(src, dst, uastc_all=False):
    if shutil.which("basisu") is None:
        raise SystemExit("basisu not found (brew install basis_universal)")
    doc, blob = read_glb(src)
    chunks = [bytes(blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]) for v in doc["bufferViews"]]
    normal_imgs, linear_imgs = set(), set()
    for m in doc.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for key, t in (("normal", m.get("normalTexture")), ("linear", m.get("occlusionTexture")),
                       ("linear", pbr.get("metallicRoughnessTexture"))):
            if t is not None:
                (normal_imgs if key == "normal" else linear_imgs).add(doc["textures"][t["index"]]["source"])
    tmp = tempfile.mkdtemp()
    for i, img in enumerate(doc.get("images", [])):
        ext = {"image/png": ".png", "image/jpeg": ".jpg"}.get(img.get("mimeType"))
        if ext is None:
            continue
        raw = os.path.join(tmp, f"{i}{ext}")
        open(raw, "wb").write(chunks[img["bufferView"]])
        out = os.path.join(tmp, f"{i}.ktx2")
        mode = ["-uastc", "-uastc_rdo_l", "1.0"] if (uastc_all or i in normal_imgs) else ["-q", "255"]
        if i in normal_imgs:
            mode += ["-normal_map"]
        elif i in linear_imgs:
            mode += ["-linear"]
        subprocess.run(["basisu", "-ktx2", "-mipmap", *mode, raw, "-output_file", out], check=True,
                       stdout=subprocess.DEVNULL)
        chunks[img["bufferView"]] = open(out, "rb").read()
        img["mimeType"] = "image/ktx2"
        img.pop("name", None)
    for t in doc.get("textures", []):
        if "source" in t:
            t.setdefault("extensions", {})["KHR_texture_basisu"] = {"source": t.pop("source")}
    for key in ("extensionsUsed", "extensionsRequired"):
        doc[key] = sorted(set(doc.get(key, [])) | {"KHR_texture_basisu"})
    write_glb(dst, doc, chunks)
    shutil.rmtree(tmp)


if __name__ == "__main__":
    convert(sys.argv[1], sys.argv[2])
