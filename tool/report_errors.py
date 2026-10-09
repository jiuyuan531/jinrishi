"""构建失败时，把日志里的关键错误整理成 GitHub 注解，方便在网页上直接查看。"""
import pathlib
import re
import sys

log = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build.log")
if not log.exists():
    print("::error::no build log")
    sys.exit(0)

lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
pat = re.compile(r"(error|Error|ERROR|What went wrong|FAILURE|Exception|e: |\.dart:\d+:\d+|undefined|isn't defined|not found|Could not)", re.I)
keep = []
for i, line in enumerate(lines):
    if pat.search(line):
        keep.extend(lines[max(0, i - 1): i + (12 if 'went wrong' in line or 'AAR metadata' in line else 3)])
seen = set()
out = []
for l in keep:
    if l not in seen:
        seen.add(l)
        out.append(l)
text = "\n".join(out[-120:]) or "\n".join(lines[-80:])


def esc(s: str) -> str:
    return s.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


# 分段输出，每段一个注解
chunk = []
size = 0
parts = []
for l in text.splitlines():
    chunk.append(l)
    size += len(l)
    if size > 3500:
        parts.append("\n".join(chunk))
        chunk, size = [], 0
if chunk:
    parts.append("\n".join(chunk))
for p in parts[:9]:
    print(f"::error title=build::{esc(p)}")
