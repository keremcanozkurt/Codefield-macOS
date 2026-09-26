import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { trySymlink, writeFiles } from "../../upstream/src/lib/local/testing.ts";
import { MAX_SOURCE_FILE_BYTES } from "../../upstream/src/lib/resources.ts";

export type Fixture = { name: string; create(root: string): Promise<void> };

export const FIXTURES: Fixture[] = [
  { name: "an empty folder", create: async () => {} },
  {
    name: "a folder without supported files",
    create: (root) => writeFiles(root, { "README.md": "# demo", "package.json": "{}" }),
  },
  {
    name: "TypeScript with a tsconfig path alias",
    create: (root) =>
      writeFiles(root, {
        "tsconfig.json": JSON.stringify({ compilerOptions: { baseUrl: ".", paths: { "@/*": ["src/*"] } } }),
        "src/index.ts": 'import { a } from "@/lib/a";\nimport "./side";\nexport * from "./lib/b";\n',
        "src/side.ts": "export {};\n",
        "src/lib/a.ts": 'import { b } from "./b";\nexport const a = b;\n',
        "src/lib/b.ts": 'import { a } from "./a";\nexport const b = 1;\n',
        "node_modules/pkg/index.js": "module.exports = 1;\n",
        "dist/index.js": 'require("../src/index");\n',
      }),
  },
  {
    name: "several languages",
    create: (root) =>
      writeFiles(root, {
        "go.mod": "module example.com/app\n",
        "main.go": 'package main\nimport "example.com/app/util"\nfunc main() { util.Run() }\n',
        "util/util.go": "package util\nfunc Run() {}\n",
        "app/__init__.py": "",
        "app/models.py": "from app import helpers\n",
        "app/helpers.py": "import os\n",
        "Cargo.toml": '[package]\nname = "demo"\n',
        "src/main.rs": "mod parser;\nfn main() {}\n",
        "src/parser.rs": "pub fn parse() {}\n",
        "include/lib.h": "int f(void);\n",
        "src/lib.c": '#include "../include/lib.h"\n',
      }),
  },
  {
    name: "files that are skipped",
    create: async (root) => {
      await writeFiles(root, {
        "src/ok.ts": 'import "./large";\n',
        "src/large.ts": "x".repeat(MAX_SOURCE_FILE_BYTES + 1),
        "src/latin1.ts": new Uint8Array([0x63, 0x6f, 0x6e, 0x73, 0x74, 0x20, 0xe9]),
        "src/bom.ts": '﻿import "./ok";\n',
        "src/broken.ts": "import {",
      });
      await trySymlink(join(root, "src", "ok.ts"), join(root, "src", "link.ts"));
      await trySymlink(join(root, "src"), join(root, "linked-dir"), "dir");
    },
  },
  {
    name: "a folder whose only source file is a symbolic link",
    create: async (root) => {
      await mkdir(join(root, "real"), { recursive: true });
      await writeFile(join(root, "notes.txt"), "");
      await trySymlink(join(root, "notes.txt"), join(root, "index.ts"));
    },
  },
];
