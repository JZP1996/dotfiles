#!/usr/bin/env node
"use strict";
// run-hook-post.js — Node.js shim for PostToolUse Bash error classification
//
// Node.js shim for the shell hook implementation.
// If updating this file, update ALL run-hook.js copies across plugins.

const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const SCRIPT = "classify-bash-error.sh";

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
    process.stderr.write("run-hook-post.js: bash not found in PATH\n");
  } else if (err.stderr) {
    process.stderr.write(err.stderr);
  }
  if (err.stdout) {
    process.stdout.write(err.stdout);
  } else {
    process.stdout.write("{}");
  }
}
