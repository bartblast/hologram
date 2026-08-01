#!/usr/bin/env node

// Script to verify the manual String.Tokenizer port against the BEAM oracle, in three passes:
//
//   1. verification_elixir.txt - the dumped corpus (usable codepoints, continuations,
//      cross-script pairs, real-world names) compared result by result
//   2. every codepoint absent from classes_elixir.txt tokenized alone - all must yield
//      {:error, :empty}, checked against the constant so the sweep is exhaustive without a
//      40 MB dump
//   3. scriptsets_elixir.txt - for every usable codepoint and each of its 13 anchor bits, the
//      pair [anchor, codepoint] must tokenize fully when and only when the bit says so
//
// The mixed-script explanation text is not compared - the port simplifies it (see the module).

import fs from "fs";

import {fileURLToPath} from "url";
import {dirname} from "path";

import Elixir_String_Tokenizer from "../../assets/js/elixir/string/tokenizer.mjs";
import Type from "../../assets/js/type.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

// The generators write the oracle files without a trailing newline, so splitting
// on it yields only real lines. An editor that adds one on save would otherwise
// feed an empty line to each pass below, which reads as a mismatch of its own.
const readLines = (file) =>
  fs
    .readFileSync(file, "utf8")
    .split("\n")
    .filter((line) => line !== "");

const tokenize = (codepoints) =>
  Elixir_String_Tokenizer["tokenize/1"](
    Type.list(codepoints.map((codepoint) => Type.integer(codepoint))),
  );

const listValues = (term) => term.data.map((item) => Number(item.value));

const serializeResult = (result) => {
  const [tag] = result.data;

  if (tag.value !== "error") {
    const [kind, acc, rest, length, ascii, special] = result.data;

    return (
      `ok:${kind.value}:${listValues(acc).join(",")}:${listValues(rest).join(",")}` +
      `:${length.value}:${ascii.value}:${special.data.map((s) => s.value).join(",")}`
    );
  }

  const reason = result.data[1];

  if (reason.type === "atom") {
    return `error:${reason.value}`;
  }

  const [reasonTag, acc] = reason.data;

  return `error:${reasonTag.value}:${listValues(acc).join(",")}`;
};

let failureCount = 0;

const report = (label, input, expected, actual) => {
  failureCount++;

  if (failureCount <= 20) {
    console.log(`MISMATCH (${label}) [${input}]`);
    console.log(`  expected ${expected}`);
    console.log(`  actual   ${actual}`);
  }
};

// Pass 1: the dumped corpus.
const corpusLines = readLines(__dirname + "/verification_elixir.txt");

console.log(`Pass 1: corpus (${corpusLines.length} inputs)...`);

for (const line of corpusLines) {
  const [inputPart, expected] = line.split("|");
  const codepoints = inputPart === "" ? [] : inputPart.split(",").map(Number);

  const actual = serializeResult(tokenize(codepoints));

  if (actual !== expected) {
    report("corpus", inputPart, expected, actual);
  }
}

// Pass 2: every unusable codepoint alone yields {:error, :empty}.
console.log("Pass 2: unusable single codepoints...");

const usable = new Set();

for (const line of readLines(__dirname + "/classes_elixir.txt")) {
  const [codepoint, start, continues] = line.split(":");

  if (!(start === "error" && continues === "0")) {
    usable.add(Number(codepoint));
  }
}

for (let codepoint = 0; codepoint <= 0x10ffff; codepoint++) {
  if (usable.has(codepoint)) {
    continue;
  }

  const actual = serializeResult(tokenize([codepoint]));

  if (actual !== "error:empty") {
    report("unusable", String(codepoint), "error:empty", actual);
  }
}

// Pass 3: anchor combinations against the script signatures.
console.log("Pass 3: script signatures...");

// Anchor order must match generate_scriptsets.exs.
const anchors = [
  0x61, 0x03b1, 0x0430, 0x05d0, 0x0627, 0x0905, 0x4e00, 0x3042, 0x30a2, 0xac00,
  0x0e01, 0x10d0, 0x0531,
];

for (const line of readLines(__dirname + "/scriptsets_elixir.txt")) {
  const [codepointPart, signature] = line.split(":");

  if (signature === "-") {
    continue;
  }

  const codepoint = Number(codepointPart);

  for (let index = 0; index < anchors.length; index++) {
    const result = tokenize([anchors[index], codepoint]);
    const [tag, , rest] = result.data;

    const combines =
      tag.value !== "error" && rest !== undefined && rest.data.length === 0;

    const expected = signature[index] === "1";

    if (combines !== expected) {
      report(
        "signature",
        `${anchors[index]},${codepoint}`,
        `combines=${expected}`,
        `combines=${combines}`,
      );
    }
  }
}

if (failureCount === 0) {
  console.log("OK: the port matches the oracle on every check");
} else {
  console.log(`FAIL: ${failureCount} mismatches`);
  process.exit(1);
}
