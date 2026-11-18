#!/usr/bin/env python3
"""Replace one exact string inside a file of an Electron asar archive, keeping its integrity hashes valid."""
import hashlib, json, struct, sys

def main(asar, member, old, new):
    raw = open(asar, "rb").read()
    header_size = struct.unpack_from("<I", raw, 4)[0]
    json_len = struct.unpack_from("<I", raw, 12)[0]
    header = json.loads(raw[16:16 + json_len])
    base = 8 + header_size

    node = header
    for part in member.split("/"):
        node = node["files"][part]
    start, size = int(node["offset"]), node["size"]
    content = raw[base + start:base + start + size]
    old_b, new_b = old.encode(), new.encode()
    if content.count(old_b) != 1:
        sys.exit(f"{member}: expected exactly one match, found {content.count(old_b)}")
    content = content.replace(old_b, new_b)
    delta = len(content) - size

    def shift(n):
        for child in n.get("files", {}).values():
            if "files" in child:
                shift(child)
            elif "offset" in child and int(child["offset"]) > start:
                child["offset"] = str(int(child["offset"]) + delta)
    shift(header)

    node["size"] = len(content)
    if "integrity" in node:
        block = node["integrity"]["blockSize"]
        blocks = [hashlib.sha256(content[i:i + block]).hexdigest() for i in range(0, len(content), block)]
        node["integrity"].update(hash=hashlib.sha256(content).hexdigest(), blocks=blocks)

    js = json.dumps(header, separators=(",", ":")).encode()
    padded = js + b"\0" * (-len(js) % 4)
    pickle = struct.pack("<II", len(padded) + 4, len(js)) + padded
    out = struct.pack("<II", 4, len(pickle)) + pickle
    data = raw[base:]
    out += data[:start] + content + data[start + size:]
    open(asar, "wb").write(out)

if __name__ == "__main__":
    main(*sys.argv[1:5])
