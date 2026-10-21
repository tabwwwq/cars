"""Static check of Roblox API usage against a Full-API-Dump.json.

Usage: python3 tools/check_api.py <Full-API-Dump.json> [src]

The dump is published at
https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json

Checks (heuristic, but catches typos that only show up at runtime in Studio):
  * Instance.new("X") / GetService("X") / IsA("X") / FindFirstChildOfClass("X") class names
  * Enum.Type.Item names
  * capitalized `.Member =` assignments and `Member = ` keys in Kit.* / Build.* prop tables
  * capitalized `:Method(` calls
Members that are not in the API dump and not defined by our own modules are reported.
"""
import json
import os
import re
import sys

dump = json.load(open(sys.argv[1]))
root = sys.argv[2] if len(sys.argv) > 2 else "src"

classes = {c["Name"]: c for c in dump["Classes"]}
enums = {e["Name"]: {i["Name"] for i in e["Items"]} for e in dump["Enums"]}
members = set()
props = set()
funcs = set()
live = set()  # names with at least one non-deprecated definition
for c in dump["Classes"]:
    for m in c["Members"]:
        if "Deprecated" not in [t for t in m.get("Tags", []) if isinstance(t, str)]:
            live.add(m["Name"])
        members.add(m["Name"])
        if m["MemberType"] == "Property":
            props.add(m["Name"])
        elif m["MemberType"] == "Function":
            funcs.add(m["Name"])
        elif m["MemberType"] == "Callback":
            props.add(m["Name"])  # callbacks are assigned like properties

# datatype members/methods (not in the class dump)
datatype_members = {
    "X", "Y", "Z", "Magnitude", "Unit", "Position", "LookVector", "RightVector", "UpVector",
    "XVector", "YVector", "ZVector", "Rotation", "R", "G", "B", "Scale", "Offset", "Min", "Max",
    "Keypoints", "Width", "Height",
    # RaycastParams / OverlapParams
    "FilterDescendantsInstances", "FilterType", "IgnoreWater", "RespectCanCollide", "CollisionGroup",
    "BruteForceAllSlow", "MaxParts",
}
datatype_methods = {
    "Dot", "Cross", "Lerp", "Inverse", "ToObjectSpace", "ToWorldSpace", "PointToWorldSpace",
    "PointToObjectSpace", "VectorToWorldSpace", "VectorToObjectSpace", "GetComponents",
    "ToEulerAnglesXYZ", "ToEulerAnglesYXZ", "ToOrientation", "ToAxisAngle", "FuzzyEq", "Abs",
    "Floor", "Ceil", "Sign", "Min", "Max", "ToHSV", "ToHex", "NextNumber", "NextInteger",
    "NextUnitVector", "Shuffle", "Clone", "AddToFilter", "Connect", "Once", "Wait", "Disconnect",
    "Fire", "DisconnectAll", "Play", "Pause", "Cancel", "ExpandToGrid", "GetCurrentPage",
    "AdvanceToNextPageAsync",
}

files = []
for d, _, fs in os.walk(root):
    for f in fs:
        if f.endswith(".luau"):
            files.append(os.path.join(d, f))

# names our own modules define: `Module.Name =`, `function Module.Name`, `local Name`, table keys in data
own = set()
for path in files:
    src = open(path).read()
    own.update(re.findall(r"\b[A-Z]\w*\.([A-Z]\w*)\s*=", src))
    own.update(re.findall(r"function\s+\w+[.:]([A-Z]\w*)", src))
    own.update(re.findall(r"local\s+function\s+([A-Z]\w*)", src))

problems = []


def report(path, line, msg):
    problems.append(f"{path}:{line}: {msg}")


for path in files:
    lines = open(path).read().split("\n")
    for n, line in enumerate(lines, 1):
        if "api-ok" in line:
            continue  # explicit opt-out, e.g. a fallback for older engines
        code = line.split("--")[0]
        for cls in re.findall(r'Instance\.new\("(\w+)"', code):
            if cls not in classes:
                report(path, n, f"unknown class {cls}")
        for cls in re.findall(r'(?:GetService|IsA|FindFirstChildOfClass|FindFirstChildWhichIsA|FindFirstAncestorOfClass|FindFirstAncestorWhichIsA)\("(\w+)"', code):
            if cls not in classes:
                report(path, n, f"unknown class {cls}")
        for et, item in re.findall(r"\bEnum\.(\w+)\.(\w+)", code):
            if et not in enums:
                report(path, n, f"unknown enum Enum.{et}")
            elif item not in enums[et]:
                report(path, n, f"unknown enum item Enum.{et}.{item}")
        for m in re.findall(r"[\w\)\]]\.([A-Z]\w*)\s*(?:[+\-*/]?=)(?!=)", code):
            if m not in props and m not in own and m not in datatype_members:
                report(path, n, f"unknown property {m}")
            elif m in props and m not in live and m not in own:
                report(path, n, f"deprecated property {m}")
        for m in re.findall(r":([A-Z]\w*)\(", code):
            if m not in funcs and m not in own and m not in datatype_methods and m not in members:
                report(path, n, f"unknown method {m}")
            elif m in funcs and m not in live and m not in own and m not in datatype_methods:
                report(path, n, f"deprecated method {m}")

    # keys inside Kit.*({ ... }) / Build.part({ ... }) / Kit.new("X", { ... }) property tables
    src = "\n".join(lines)
    kit_classes = {"label": "TextLabel", "button": "TextButton", "panel": "Frame"}
    matches = [(m, m.group(1)) for m in re.finditer(r'Kit\.new\("(\w+)",\s*\{', src)]
    matches += [(m, kit_classes[m.group(1)]) for m in re.finditer(r"Kit\.(label|button|panel)\(\{", src)]
    for mt, cls in matches:
        depth, i = 1, mt.end()
        while i < len(src) and depth:
            if src[i] == "{":
                depth += 1
            elif src[i] == "}":
                depth -= 1
            i += 1
        body = src[mt.end(): i - 1]
        # only top-level keys
        level = 0
        for k in re.finditer(r"[{}]|\b([A-Z]\w*)\s*=(?!=)", body):
            tok = k.group(0)
            if tok == "{":
                level += 1
            elif tok == "}":
                level -= 1
            elif level == 0 and k.group(1):
                name = k.group(1)
                if name == "Parent" or name in ("onClick", "cornerRadius"):
                    continue
                c = classes.get(cls)
                found = False
                while c:
                    if any(m["Name"] == name for m in c["Members"]):
                        found = True
                        break
                    c = classes.get(c.get("Superclass"))
                if not found:
                    line = src[: mt.start()].count("\n") + 1
                    report(path, line, f"{cls} has no property {name}")

errors = [p for p in problems if "deprecated" not in p]
for p in problems:
    print(("warning: " if "deprecated" in p else "error: ") + p)
print(f"{len(errors)} error(s), {len(problems) - len(errors)} warning(s) in {len(files)} files")
sys.exit(1 if errors else 0)
