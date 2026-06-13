#!/usr/bin/env python3
# #cursor generated code - start
"""Strip artifact-content arrays from metadata.json for builder input shape."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("metadata_json", type=Path)
    p.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write here (default: overwrite input)",
    )
    args = p.parse_args()
    path = args.metadata_json
    data = json.loads(path.read_text(encoding="utf-8"))
    for row in data.get("artifact-meta-data", []):
        row.pop("artifact-content", None)
    out = args.output or path
    out.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
# #cursor generated code - end
