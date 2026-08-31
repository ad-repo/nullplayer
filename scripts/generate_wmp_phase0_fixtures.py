#!/usr/bin/env python3
"""Generate NullPlayer-owned deterministic Phase 0 WMP fixtures."""

from pathlib import Path
import binascii
import struct
import zipfile


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Tests/NullPlayerAppTests/Fixtures/WMPSkin"
STAMP = (1980, 1, 1, 0, 0, 0)


def info(name: str, *, symlink: bool = False) -> zipfile.ZipInfo:
    item = zipfile.ZipInfo(name, STAMP)
    item.compress_type = zipfile.ZIP_DEFLATED
    item.create_system = 3
    item.external_attr = ((0o120777 if symlink else 0o100644) << 16)
    return item


def archive(name: str, entries, *, stored: bool = False) -> Path:
    path = OUT / name
    with zipfile.ZipFile(path, "w", allowZip64=True) as output:
        for entry_name, payload, is_symlink in entries:
            item = info(entry_name, symlink=is_symlink)
            if stored:
                item.compress_type = zipfile.ZIP_STORED
            output.writestr(item, payload)
    return path


def bmp(width: int, height: int, colors=None) -> bytes:
    colors = colors or [(0x22, 0x44, 0x66)] * (width * height)
    row_size = ((width * 3 + 3) // 4) * 4
    pixels = bytearray()
    for y in range(height - 1, -1, -1):
        row = bytearray()
        for x in range(width):
            red, green, blue = colors[y * width + x]
            row.extend((blue, green, red))
        row.extend(b"\0" * (row_size - width * 3))
        pixels.extend(row)
    header = b"BM" + struct.pack("<IHHI", 54 + len(pixels), 0, 0, 54)
    dib = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    return header + dib + pixels


def patch_declared_sizes(path: Path, sizes, compressed_sizes=None) -> None:
    data = bytearray(path.read_bytes())
    local = 0
    central = data.find(b"PK\x01\x02")
    compressed_sizes = compressed_sizes or [0] * len(sizes)
    for size, compressed_size in zip(sizes, compressed_sizes):
        if data[local:local + 4] != b"PK\x03\x04":
            raise RuntimeError("missing local header")
        struct.pack_into("<III", data, local + 14, 0, compressed_size, size)
        if data[central:central + 4] != b"PK\x01\x02":
            raise RuntimeError("missing central header")
        struct.pack_into("<III", data, central + 16, 0, compressed_size, size)
        name_length = struct.unpack_from("<H", data, local + 26)[0]
        extra_length = struct.unpack_from("<H", data, local + 28)[0]
        local += 30 + name_length + extra_length
        central_name = struct.unpack_from("<H", data, central + 28)[0]
        central_extra = struct.unpack_from("<H", data, central + 30)[0]
        central_comment = struct.unpack_from("<H", data, central + 32)[0]
        central += 46 + central_name + central_extra + central_comment
    path.write_bytes(data)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.iterdir():
        if old.is_file():
            old.unlink()

    simple = '<?xml version="1.0"?><THEME><VIEW id="main" width="320" height="80"/></THEME>\n'
    (OUT / "utf8.wms").write_bytes(simple.encode("utf-8"))
    (OUT / "utf16le.wms").write_bytes(b"\xff\xfe" + simple.encode("utf-16le"))
    (OUT / "utf16be.wms").write_bytes(b"\xfe\xff" + simple.encode("utf-16be"))

    widgets = """<?xml version="1.0" encoding="UTF-8"?>
<THEME scriptFile="normal-return.js;host-read-write.js">
  <VIEW id="main" width="320" height="120">
    <SUBVIEW id="nested" left="4" top="4" width="300" height="100">
      <TEXT id="title" left="8" top="8" width="120" height="16" value="NullPlayer fixture"/>
      <IMAGE id="logo" left="8" top="28" width="2" height="2" image="pixel.bmp"/>
      <BUTTON id="plain" left="20" top="28" width="24" height="16" onClick="JScript:callback('plain');"/>
      <BUTTONGROUP id="mapped" left="52" top="28" width="4" height="1" mappingImage="mapping.bmp" image="mapping.bmp">
        <BUTTONELEMENT id="red" mappingColor="#FF0000"/>
        <BUTTONELEMENT id="green" mappingColor="#00FF00"/>
      </BUTTONGROUP>
      <SLIDER id="volume" left="8" top="52" width="100" height="12" value="wmpprop:player.settings.volume"/>
    </SUBVIEW>
  </VIEW>
</THEME>
"""
    (OUT / "widgets.wms").write_text(widgets, encoding="utf-8")

    scripts = {
        "normal-return.js": "21 * 2;\n",
        "host-read-write.js": "player.settings.volume = 0.75; player.settings.volume;\n",
        "callback.js": "callback('ready'); 'done';\n",
        "syntax-error.js": "function broken( {\n",
        "recursion.js": "function recurse(){ return recurse(); } recurse();\n",
        "timer-storm.js": "for (var i=0;i<10000;i++) setTimeout(function(){callback('tick')}, 0); 'queued';\n",
        "allocation-pressure.js": "var blocks=[]; while(true){ blocks.push(new ArrayBuffer(1048576)); }\n",
        "infinite-loop.js": "while (true) {}\n",
    }
    for name, source in scripts.items():
        (OUT / name).write_text(source, encoding="utf-8")

    pixels = bmp(2, 2)
    mapping = bmp(4, 1, [(255, 0, 0), (255, 0, 0), (0, 255, 0), (0, 255, 0)])
    valid_entries = [("widgets.wms", widgets.encode(), False), ("pixel.bmp", pixels, False),
                     ("mapping.bmp", mapping, False)]
    valid_entries += [(name, source.encode(), False) for name, source in scripts.items()]
    archive("widgets.wmz", valid_entries)
    archive("wrapper-directory.wmz", [("Fixture/skin.wms", simple.encode(), False),
                                       ("Fixture/pixel.bmp", pixels, False)])
    two_view = simple.replace("</THEME>", '<VIEW id="compact" width="160" height="40"/></THEME>')
    archive("two-view.wmz", [("skin.wms", two_view.encode(), False)])

    archive("traversal.wmz", [("../escape.wms", simple.encode(), False)])
    archive("absolute-path.wmz", [("/escape.wms", simple.encode(), False)])
    archive("drive-path.wmz", [("C:\\escape.wms", simple.encode(), False)])
    archive("case-collision.wmz", [("Skin.wms", simple.encode(), False),
                                    ("skin.WMS", simple.encode(), False)])
    archive("symlink.wmz", [("skin.wms", simple.encode(), False), ("link.bmp", b"pixel.bmp", True)])
    archive("wrapper-too-deep.wmz", [("one/two/skin.wms", simple.encode(), False)])
    archive("excess-entries.wmz", [(f"entries/{index:04}.txt", b"", False) for index in range(4097)])
    archive("excess-ratio.wmz", [("ratio.bin", b"A" * 65536, False)])

    entry_bytes = archive("excess-entry-bytes.wmz", [("huge.bin", b"", False)], stored=True)
    patch_declared_sizes(entry_bytes, [32 * 1024 * 1024 + 1])
    archive_bytes = archive("excess-archive-bytes.wmz",
                            [(f"part-{index}.bin", b"", False) for index in range(5)], stored=True)
    patch_declared_sizes(archive_bytes, [32 * 1024 * 1024] * 5, [32 * 1024 * 1024] * 5)

    deep = "<?xml version=\"1.0\"?>" + "<SUBVIEW>" * 257 + "</SUBVIEW>" * 257
    archive("deep-xml.wmz", [("deep.wms", deep.encode(), False)], stored=True)
    many_nodes = "<?xml version=\"1.0\"?><THEME>" + "<TEXT/>" * 100001 + "</THEME>"
    archive("excess-xml-nodes.wmz", [("nodes.wms", many_nodes.encode(), False)], stored=True)
    archive("oversized-image.wmz", [("skin.wms", simple.encode(), False),
                                     ("huge.bmp", bmp(1, 1)[:18] + struct.pack("<ii", 8193, 8193) + bmp(1, 1)[26:], False)])
    archive("oversized-script.wmz", [("skin.wms", simple.encode(), False),
                                      ("huge.js", b" " * (4 * 1024 * 1024 + 1), False)])

    corrupt = archive("crc-corrupt.wmz", [("skin.wms", simple.encode(), False)], stored=True)
    raw = bytearray(corrupt.read_bytes())
    payload_offset = 30 + struct.unpack_from("<H", raw, 26)[0] + struct.unpack_from("<H", raw, 28)[0]
    raw[payload_offset] ^= 0x01
    corrupt.write_bytes(raw)

    manifest = [
        "All files in this directory are original synthetic fixtures authored for NullPlayer.",
        "They contain no Microsoft or community skin code or artwork.",
        "Regenerate deterministically with scripts/generate_wmp_phase0_fixtures.py.",
        "",
    ]
    for path in sorted(OUT.iterdir()):
        if path.name != "MANIFEST.txt":
            manifest.append(f"{path.name}\t{path.stat().st_size}\t{binascii.hexlify(__import__('hashlib').sha256(path.read_bytes()).digest()).decode()}")
    (OUT / "MANIFEST.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
