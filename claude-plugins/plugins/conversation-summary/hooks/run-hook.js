#!/usr/bin/env node
"use strict";
// run-hook.js — Node.js shim for cross-platform hook execution
//
// Node.js shim for the shell hook implementation.
// If updating this file, update ALL run-hook.js copies across plugins.
//
// On Windows, Claude Code spawns hook commands via:
//   cmd.exe /d /s /c "command"
// This can misparse paths containing spaces when invoking bash directly.
//
// This shim uses child_process.execFileSync with an argv array, which
// bypasses shell interpretation for the bash invocation — the script path
// is passed directly via CreateProcess (no cmd.exe re-interpretation).
//
// stdin/stdout are piped through so the bash script receives Claude Code's
// JSON input and its JSON output reaches Claude Code.

const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const SCRIPT = "summarize-context.sh";

let input = "";
try {
  input = fs.readFileSync(0, "utf8");
} catch {
  // stdin may be empty or closed
}

try {
  const result = execFileSync("bash", [path.join(__dirname, SCRIPT)], {
    input,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  });
  if (result) process.stdout.write(result);
} catch (err) {
  if (err.code === "ENOENT") {
    process.stderr.write("run-hook.js: bash not found in PATH\n");
  } else if (err.stderr) {
    process.stderr.write(err.stderr);
  }
  if (err.stdout) {
    process.stdout.write(err.stdout);
  } else {
    process.stdout.write("{}");
  }
}
