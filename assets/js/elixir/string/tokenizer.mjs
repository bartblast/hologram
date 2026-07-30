"use strict";

import Interpreter from "../../interpreter.mjs";
import Type from "../../type.mjs";

// Manual port of Elixir's String.Tokenizer, whose transpiled form encodes the UTS 39 identifier
// tables as one guard clause per codepoint range and would cost the bundle ~39 KB gzipped. The
// port keeps the driving logic from lib/elixir/unicode/tokenizer.ex and replaces the generated
// clauses with the range table below, the browser's own script data (Script_Extensions regexes),
// and native NFC normalization.
//
// One simplification, in the shape Elixir's own tokenize/1 callers permit: the mixed-script
// error's human-readable explanation lists each character without its script names, since naming
// them would need the script tables the port exists to avoid. The error's structure, its
// characters and its leading text match the server.

// The BEAM's identifier classification of every Unicode codepoint, from UTS 39's
// IdentifierType.txt as Elixir's String.Tokenizer applies it. Carried as data because no native
// JavaScript property expresses it - see scripts/identifier_tokenizer/ for the derivation and the
// comparison against the closest native approximation.
//
// Encoding: base36 delta string - per range, gap-from-previous-range-end "." length, then the
// range's class letter: I identifier start, A atom start (uppercase non-ASCII), L alias start
// (A-Z), C continues only. All four classes may continue an identifier. Codepoints outside every
// range are unusable.
//
// GENERATED RANGES START - regenerate with: node scripts/identifier_tokenizer/generate_table.mjs
const ENCODED_RANGES =
  "x.0Cf.9C6.1C1.pL5.0I2.pI1n.0I2.0C9.mA2.6A1.nI2.7I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I2.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I2.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.1A1.0I1.0A1.0I1.0A1.0I3.0A5.0A3.1A4.3A1.0I2.0A2.2A1.0I4.0A3.0A1.0Ie.0A1.0I2.1A1.0I3.0Am.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I9.0I9.0A1.0I1.0A1.0I5.0A1.0I9.0A1.0Iv.0A1.0I1.0A1.0I15.0A8.0A1.0I6.1I2.1I2.0I2.0I8.0I5.1I9.0In.0I2.0I7.0I15.1I1w.4C2.6Cf.0C8.0C3.2C9.0C2d.0A2.2A2.0A2.1A1.0I1.gA2.8A1.yI1f.bA2.xA1.vI2.bI2.1I1d.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0Af.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I5.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I3.0A1.0I17.0A1.0Ic.11Ab.11I22.qI1i.qI3.0I4.9I1.7C2.1Cb.9C7.0C2.0I2.0I5.mI2.9I5.1I2.0I2.7I2.4I2.0I2.2I3.4I2.jI2.0Ip.1I1.9C6.0I2a.1I4.0Ia.0I2.1I3.2I2.0I4.3If.11I1.aC1.0I66.0Ih.0I2.7Ii.7I5.0I1m.2C2.6I2.rI2.9I2.4I1.2C2.5C2.8C2.0C7.1Cf.9C3.5I4.1I2.1I2.2C2.6I4.1I3.lI2.6I2.0I4.3I3.0C2.6C3.1C3.2C1.0Io.9C1.1Ih.0C3.5I5.1I3.lI2.6I2.0I3.0I3.1I3.0C2.4C5.1C3.2Cf.0Ik.1Ch.1C2.8I2.2I2.lI2.6I2.1I2.4I3.0C2.7C2.2C2.2Cp.9Ci.2C2.6I4.1I3.lI2.6I2.1I3.3I3.0C2.5C4.1C3.2C9.0C9.0Ii.0Ii.0I2.5I4.2I2.3I4.1I2.0I2.1I4.1I4.2I4.bI5.4C4.2C2.3C1h.1C2.6I3.2I2.mI2.6I2.1I2.4I5.6C2.2C2.3C1h.1C2.6I3.2I2.mI2.6I2.1I2.4I5.5C3.2C2.3Cp.9Cj.1C2.6I3.2I2.mI2.fI5.5C3.2C2.1C2.0Ca.0Cz.5I3.1C2.8I4.5I4.3I2.iI2.8I2.0I3.6I4.0C5.5C2.0C2.6Ck.0Cf.1bI1.0C1.0I2.6C6.6I1.6C3.9C14.1I2.0I3.1I2.0I3.0I7.3I2.6I2.2I2.0I2.0I3.1I2.1I2.0I1.0C1.0I2.5C2.1C1.0I3.4I2.0I2.5C3.9C1z.9Cn.2I2.3I2.3I2.3I2.3I2.3I2.bI9.1C2.0C6.6C4.0Cc.2C2.3C2.3C2.3C2.3C2.3C2.0C4.7C2.2C1w.16I1.jC1.0I1.9Ch.3I1.2C1.0I1.2Ch.cI1.8C5.0C1k.0A6.0A3.wI7k.6I2.1sI2.3I3.6I2.0I2.3I3.12I2.0I2.3I3.uI2.0I2.3I3.6I2.0I2.3I3.eI2.vI9.eI2.0I2.3I3.6I2.12I2.hItj.sI3.3I3.2I3.9I3.nC3.0C2.0Ce.9Cx3.16A3.2A99.0A1.0I5.0A1.0Id.0A1.0I3.0A1.0Ih.0A1.0I5.0A1.0I1.0A1.0I3.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0If.0A1.0I7.0A1.0I9.0A1.0I3.0A1.0Ir.0A1.0I5.0A1.0Ib.0A2.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I1.0A1.0I4n.7I1.7A3.2I1k.0A36h.2I1m.2dI7.1I3.2hI1.0C1.2Ind.0I18.0I35.0I43.0I13.0I3.0Ic.0Ii.0If.0I11.0Ib.0Ig.0Ic.0Ila.0I20.0Ie.0I2p.1Ib.0I4.0Ip.0I6.0Iq.0I1m.0Ia.0Ib.0Ic.0I5i.0Il.0I2d.0I5n.0I36.0I7b.0I4.0I3t.0I2k.0Iau.0If.0I5.0I29.0I10.0I2g.0I14.0Id4.0I39.0I5.0Iy.0Ia.0I2u.0I43.0Ik.0I7w.0I1y.0Il.0I5e.0I6.0I2b.0Ih.0I2v.0I3y.0I5h.0I1f.0I3.0I5.1I2.1Il.0I4.0In.1I2j.0I4m.0Icf.0I6.0I4.0I4.0Io.6I34.6I45.0I2a.hI2.lI2.1pI2.fI2.rI2.bI2.nI2.eI2.pI2.fI4.0I2.0I2.7I2.dI2.gI2.7I2.2I2.0I2.7I2.2I2.17I2.pI2.0I2.iI2.pI2.7I2.0I2.2I2.kI2.oI3.hI2.yI2.2I2.3I2.3I2.eI2.4I2.yI2.3I2.gI2.2I2.6I4.mI2.8I2.jI2.5I2.0I3.7I2.7I2.1I2.yI2.bI2.1I2.lI2.6I2.3I2.2I2.3I2.6I2.2I2.cI2.aI2.3I3.8I2.hI2.0I2.8I2.9I2.0I2.6I2.eI3.aI2.bI2.0I2.2I2.2nI2.hI2.hI2.aI2.7I2.1gI2.2I2.2I2.0I2.1I2.1I2.bI2.2I2.7I2.jI3.iI2.1I2.1I2.7I2.0I2.7I2.1I3.aI2.nI2.0I2.bI2.1I2.hI2.vI2.7I3.2I2.9I2.9I2.8I2.cI3.7I2.mI3.oI2.6I2.14I2.fI2.aI2.vI2.15I2.1rI2.tI2.1I3.18I2.nI2.oI2.2sI2.mI2.gI3.jI2.9I2.aI2.3I2.6I2.5I2.4I2.3I2.7I2.0I2.iI2.6I2.9I2.1I2.9I2.6I2.qI2.jI2.8I2.bI2.eI2.0I2.1I3.7I2.aI2.4I2.8I2.1I2.nI2.4I2.3I2.bI3.0I2.9I2.jI2.7I2.4I2.dI2.gI2.wI2.5I2.8I2.1mI3.1iI2.4I2.8I2.4I3.eI2.sI2.jI2.aI2.8I2.1I3.7I2.1I2.fI2.3I2.dI2.aI2.2I2.1I2.7I2.0I2.eI2.eI2.1I2.xI2.0I2.2iI2.1aI2.1nI2.0I2.4I2.2I2.yI2.3I2.kI2.0I2.kI2.4I2.sI2.12I2.qI3.oI2.1I2.16I2.bI2.7I2.1I2.cI3.cI2.8I2.3I2.6I2.8I2.nI2.7I2.3I2.3I2.aI2.gI2.10I2.pI2.6I2.1I2.1I2.bI2.yI2.15I2.19I2.3I2.qI2.6I2.mI2.1gI2.2I2.aI2.mI2.2I2.7I2.xI2.hI2.bI3.5I2.6I2.4I2.9I2.hI2.1I2.0I2.oI2.qI2.1gI2.7I2.1rI2.12I2.4I2.15I2.cI2.jI2.17I2.0I2.28I2.9I2.7I3.aI2.gI2.aI2.bI2.5I2.8I2.eI2.11I2.1dI2.9I2.eI2.1I2.rI2.0I2.gI2.17I2.2I2.6I2.5I2.mI2.3I2.3I2.8I2.bI2.hI2.0I2.0I2.1I3.11I2.pI2.2I2.5I2.fI2.3I2.rI2.0I2.mI2.0I2.lI2.1I2.kI2.1aI2.2I2.sI2.1gI2.eI2.1rI2.aI2.uI2.bI2.oI2.4I2.yI2.1aI2.6I2.1oI2.2wI3.bI2.fI2.yI2.6I2.pI2.cI2.5I2.gI2.bI2.nI2.5I2.2I2.7I2.6I2.jI2.7I2.mI2.0I2.mI2.3I2.sI2.bI2.eI2.pI2.7I2.8I3.6I2.5I2.2I2.6I2.4I2.dI2.3I2.nI2.jI2.9I3.eI2.3I2.hI2.1I2.19I2.8I2.0I2.cI3.xI2.1I2.2I2.6I2.eI2.hI2.3I2.gI2.9I2.3I2.1oI2.vI2.cI2.11I2.0I2.kI2.0I2.wI2.6I2.iI2.gI2.7I2.12I2.0I2.2I2.qI2.pI2.2I2.aI2.hI2.9I2.kI2.7I2.1I2.yI2.1fI2.dI2.28I2.1I2.sI2.fI3.1I4.16I2.nI2.6I2.hI2.hI2.gI2.gI2.0I2.kI2.2I2.3I2.8I2.2I2.iI2.bI2.0I2.2I2.3I2.dI2.fI2.zI2.bI2.hI2.5I2.9I2.lI3.3I2.9I2.2I2.0I2.1I2.2I2.6I2.1lI2.1bI2.6I2.1I2.4I2.eI2.gI2.fI2.dI2.7I2.11I2.0I2.1cI2.1iI2.qI2.cI2.oI2.6I2.23I2.eI2.jI2.oI3.3I2.1yI3.0I3.2I2.aI2.4I2.gI2.wI2.uI2.dI4.cI2.8I2.1wI2.6I2.vI2.5I2.1hI2.4I2.0I2.19I2.tI2.0I2.3I2.mI2.cI2.9I2.1I2.wI2.6I2.hI2.1I2.1eI2.2I2.1I2.yI3.6I2.4I2.aI2.8I2.2I2.dI2.6I2.2I2.tI2.13I2.8I2.qI2.dI3.xI2.iI2.0I2.uI2.7I2.eI2.3I2.9I2.kI2.5I2.uI2.5I2.fI2.4I2.2I2.0I2.7I2.2I3.8I2.3I2.fI2.7I2.0I2.3I2.2cI2.hI2.1uI2.cI2.mI2.15I2.1zI2.zI2.1cI2.6I2.rI2.vI2.3I2.7I2.0I2.dI2.xI2.7I2.gI2.5I2.14I2.0I2.1I2.tI2.1fI2.vI2.fI2.1I2.7I2.1I2.eI2.8I2.8I2.yI2.cI2.zI2.gI2.1oI2.mI3.aI2.2I2.sI2.oI2.iI3.1I2.1I2.9I2.1I2.9I2.8I2.cI2.gI2.jI2.0I2.aI2.hI2.8I2.iI2.1I2.wI2.1cI2.cI2.oI2.1I2.fI2.9I2.5I2.0I2.cI3.19I2.gI2.aI2.2I2.3I2.15I2.gI2.1kI2.3I2.9I2.sI2.6I2.6I2.6I2.3I2.6I2.8I3.gI2.2I2.xI2.hI2.0I2.5I3.eI3.lI2.9I2.hI2.6I2.1I2.3I2.6I2.1I2.14I2.4I2.0I2.xI2.aI2.0I2.14I2.4I2.3I2.hI2.mI3.sI2.0I4.3I2.2I2.xI2.aI2.5I2.9I2.mI2.6I2.0I2.nI2.fI2.26I2.0I2.9I2.0I2.1yI2.vI2.hI3.xI2.1I2.6I2.nI2.fI2.aI2.5I2.gI2.11I2.5I3.4I2.0I2.0I3.kI2.1I2.yI2.5I2.1I2.pI2.3I2.bI2.8I2.iI2.8I2.hI2.1I2.aI2.2I2.zI2.4I2.gI2.4I2.gI4.nI2.1tI2.7I2.1jI2.4cI3.3I2.3I2.hI2.15I2.aI2.5I2.0I2.pI2.wI2.5I2.5I2.10I2.zI2.bI2.2I2.10I2.wI2.4I2.4I2.gI4.9I2.4I2.10I2.yI3.1aI3.25I2.aI2.4I2.1fI2.nI2.9I3.xI2.fI2.rI2.yI2.11I2.10I2.1aI2.oI2.cI2.4I2.uI2.zI2.2vI2.12I2.5I2.11I2.0I3.6I2.1jI2.15I2.gI2.wI2.aI2.14I2.mI2.9I2.wI3.nI2.2I2.19I2.iI2.tI2.7I2.fI2.wI2.3I2.7I2.5I2.8I3.0I2.3I2.6I2.oI2.uI2.sI2.iI2.7I2.cI2.4I2.19I2.9I2.5I2.kI2.uI2.gI2.cI2.6I2.16I2.rI2.9I2.1rI2.kI2.lI2.9I2.pI2.bI2.bI2.fI2.2I2.1I2.pI2.2yI2.1I2.2I2.kI2.aI2.jI2.1rI2.eI2.6I2.eI2.1I2.2I2.3I2.lI2.2I2.5I3.1cI2.5I2.2I2.2I2.6I3.cI2.3I2.5I3.8I2.gI2.cI2.nI2.iI2.3I2.9I2.lI2.eI2.6I2.nI2.qI2.1nI2.7I2.4I2.5I2.wI3.5I2.aI2.5I2.3I2.4I2.4I2.0I2.aI2.4bI2.6I2.2I2.bI4.3I2.qI2.9I2.2I2.2I2.2I2.eI2.9I2.zI2.9I2.0I2.fI2.cI2.8I2.eI3.2wI2.14I2.oI2.zI2.qI2.8I2.11I2.iI2.7I2.tI2.5I2.0I2.0I2.wI2.5I2.fI2.1I3.8I2.1I2.jI2.lI2.tI2.sI2.bI2.5I2.2iI2.5I2.dI2.eI2.5I2.rI2.1tI2.0I2.9I2.7I2.4I2.2rI2.vI3.3I2.yI2.iI2.1cI3.qI2.wI2.oI2.1I2.fI2.kI2.3I2.qI2.dI2.yI2.aI2.1I2.vI2.10I3.lI2.1I2.oI2.tI2.lI2.5I2.5I2.1kI2.iI3.1bI2.4I2.1I2.2I2.2I2.3I2.5I2.0I2.8I2.fI2.2I2.9I2.eI2.zI2.hI2.dI2.jI2.3I2.0I3.3I2.tI2.9I2.sI2.dI2.6zI3.3I2.5I2.gI2.qI3.2I2.7I2.mI2.2I2.1yI3.1I2.jI2.mI3.wI2.0I2.2I2.0I3.8I2.8I2.2I2.1I2.0I2.aI2.2I2.4I2.19I2.0I3.jI2.mI2.1I2.1I3.mI3.1I2.7I3.aI2.8I2.aI2.gI2.gI2.0I2.gI2.cI2.5I3.2I2.7I2.0I2.gI2.14I2.xI2.4I2.3I2.7I2.5I2.2I2.2I2.3I2.dI2.eI2.0I2.25I2.hI2.oI2.6I2.3I2.5I2.1I2.sI2.wI2.7I2.kI2.1I2.2oI2.vI2.4I2.3I2.8I2.pI2.5I3.xI2.kI2.5I2.3I2.4I2.1wI2.iI2.9I2.dI2.7I2.2I2.2I3.5I2.eI2.0I2.5I2.9I2.5I2.nI2.7I2.1I2.eI2.5I2.9I2.eI2.lI2.1I2.bI2.13I2.1eI2.8I3.0I2.1pI2.bI2.0I2.eI2.1I2.lI2.3zI3.2I2.kI2.cI2.5I2.1bI2.12I2.nI2.dI2.1I2.14I2.gI2.gI2.6I2.4I2.2lI2.iI3.6I2.4I2.2I2.7I3.3I2.1lI2.3I2.gI2.cI2.1I2.gI2.tI2.cI2.oI2.1eI2.0I2.1I1k8.0At.0Ak1.0Cat.8mbIbq6.0C2.0C1l.0C1604.6I2.3I2.1I2.eI64w.0Iz.0I20.0Iyi.0I11.0Iu.0I1l.0I6.0I1s.0I2v.0I3.0I3z.1I2w.0I12.0I5.0I1h.0Iy.1I1f.1Iu.0I2w.0I8.0I1a.0I36.0Ij.0I6.1I5.0I1y.0I8.0I7k.0I2y6.0I1da.0Im8.0I32.0I3r.0I3r.0I4.0I31.0I1y.0I1w.0Ir.0I98.0I2ro.0I1lo.0I1r9.0I1e.0In5.0I3e5.0I12s.0Ifa.0I8.0I37o.0I1en.0I4q.0I63.0I1yg.0I3.0I5.0I3ba.0I";
// GENERATED RANGES END

const RANGE_COUNT = (ENCODED_RANGES.match(/[IALC]/g) ?? []).length;

const RANGE_STARTS = new Uint32Array(RANGE_COUNT);
const RANGE_ENDS = new Uint32Array(RANGE_COUNT);
const RANGE_CLASSES = new Array(RANGE_COUNT);

{
  const tokenRegex = /([0-9a-z]+)\.([0-9a-z]*)([IALC])/g;
  let index = 0;
  let previousEnd = 0;
  let match;

  while ((match = tokenRegex.exec(ENCODED_RANGES)) !== null) {
    const start = previousEnd + parseInt(match[1], 36);
    const end = start + (match[2] === "" ? 0 : parseInt(match[2], 36));

    RANGE_STARTS[index] = start;
    RANGE_ENDS[index] = end;
    RANGE_CLASSES[index] = match[3];

    previousEnd = end;
    ++index;
  }
}

// Codepoint class from the carried table, or null when unusable.
const classOf = (codePoint) => {
  let low = 0;
  let high = RANGE_STARTS.length - 1;

  while (low <= high) {
    const middle = (low + high) >> 1;

    if (codePoint < RANGE_STARTS[middle]) {
      high = middle - 1;
    } else if (codePoint > RANGE_ENDS[middle]) {
      low = middle + 1;
    } else {
      return RANGE_CLASSES[middle];
    }
  }

  return null;
};

// The scripts identifiers may be written in (UTS 39 recommended scripts), by short name. Common
// and Inherited are not carried - a codepoint bearing only those has the ALL script set.
const SCRIPTS = [
  "Arab",
  "Armn",
  "Beng",
  "Bopo",
  "Cyrl",
  "Deva",
  "Ethi",
  "Geor",
  "Grek",
  "Gujr",
  "Guru",
  "Hang",
  "Hani",
  "Hebr",
  "Hira",
  "Kana",
  "Khmr",
  "Knda",
  "Laoo",
  "Latn",
  "Mlym",
  "Mymr",
  "Orya",
  "Sinh",
  "Taml",
  "Telu",
  "Thaa",
  "Thai",
  "Tibt",
];

const SCRIPT_REGEXES = new Map(
  SCRIPTS.map((script) => [script, new RegExp(`^\\p{scx=${script}}$`, "u")]),
);

const COMMON_REGEX = /^[\p{scx=Zyyy}\p{scx=Zinh}]$/u;

// Script sets are null for ALL (combines with everything) or a Set of short names, empty for
// NONE. Mirrors ScriptSet with @top as null and @bottom as the empty set.
const ALL = null;

// Codepoints whose BEAM script set differs from the browser's Script_Extensions, from
// scripts/identifier_tokenizer/comparison_scriptsets.txt: Greek mu acts script-neutral, and
// U+088F postdates the browser's Unicode tables.
const SCRIPTSET_OVERRIDES = new Map([
  [956, ALL],
  [2191, new Set(["Arab"])],
]);

const scriptSetOf = (codePoint) => {
  if (SCRIPTSET_OVERRIDES.has(codePoint)) {
    return SCRIPTSET_OVERRIDES.get(codePoint);
  }

  const char = String.fromCodePoint(codePoint);

  if (COMMON_REGEX.test(char)) {
    return ALL;
  }

  const scripts = new Set(
    SCRIPTS.filter((script) => SCRIPT_REGEXES.get(script).test(char)),
  );

  // UTS 39 augmentation: the CJK scripts also belong to the writing systems combining them.
  if (scripts.has("Hani") || scripts.has("Hira") || scripts.has("Kana")) {
    scripts.add("Jpan");
  }

  if (scripts.has("Hani") || scripts.has("Hang")) {
    scripts.add("Kore");
  }

  if (scripts.has("Hani") || scripts.has("Bopo")) {
    scripts.add("Hanb");
  }

  return scripts;
};

const LATIN = new Set(["Latn"]);

const intersect = (scriptSet1, scriptSet2) => {
  if (scriptSet1 === ALL) return scriptSet2;
  if (scriptSet2 === ALL) return scriptSet1;

  return new Set([...scriptSet1].filter((script) => scriptSet2.has(script)));
};

const isEmpty = (scriptSet) => scriptSet !== ALL && scriptSet.size === 0;

// NFC form of a single codepoint, as an array of codepoints, or null when it is NFC-stable.
const nfcExpansion = (codePoint) => {
  const char = String.fromCodePoint(codePoint);
  const normalized = char.normalize("NFC");

  if (normalized === char) {
    return null;
  }

  return Array.from(normalized).map((c) => c.codePointAt(0));
};

// Mirrors chunks_single?/1: underscore splits an identifier into chunks, each of which must be
// single-script on its own - how "fox_狐" stays valid while "fox狐" does not.
const chunksSingle = (codePoints) => {
  let chunkSet = ALL;

  for (const codePoint of codePoints) {
    if (codePoint === 95) {
      if (isEmpty(chunkSet)) {
        return false;
      }

      chunkSet = ALL;
      continue;
    }

    if (codePoint <= 127) {
      if (
        (codePoint >= 97 && codePoint <= 122) ||
        (codePoint >= 65 && codePoint <= 90)
      ) {
        chunkSet = intersect(chunkSet, LATIN);
      }

      continue;
    }

    chunkSet = intersect(chunkSet, scriptSetOf(codePoint));
  }

  return !isEmpty(chunkSet);
};

const asciiLower = (codePoint) => codePoint >= 97 && codePoint <= 122;
const asciiUpper = (codePoint) => codePoint >= 65 && codePoint <= 90;
const asciiDigit = (codePoint) => codePoint >= 48 && codePoint <= 57;

// Mirrors [name | List.delete(list, name)]: the name lands at the front whether or not it was
// already carried.
const moveToFront = (list, name) => {
  const index = list.indexOf(name);
  if (index !== -1) list.splice(index, 1);
  list.unshift(name);
};

// Mirrors continue/6. Consumes codepoints from index onward, returning
// {acc, restIndex, length, asciiLetters, scriptSet, special} or an error object. acc keeps the
// original codepoints - validate normalizes once at the end, which lands on the same NFC form as
// the server's per-character replacement.
const continueTokens = (codePoints, index, acc, asciiLetters, scriptSet) => {
  const special = [];

  while (index < codePoints.length) {
    const head = codePoints[index];

    if (head === 33 || head === 63) {
      // ! and ? close the identifier.
      acc.push(head);
      special.unshift("punctuation");

      return {acc, restIndex: index + 1, asciiLetters, scriptSet, special};
    }

    if (head === 64) {
      acc.push(head);
      moveToFront(special, "at");
      ++index;
      continue;
    }

    if (asciiLower(head) || asciiUpper(head)) {
      acc.push(head);
      scriptSet = intersect(scriptSet, LATIN);
      ++index;
      continue;
    }

    if (head === 95 || asciiDigit(head)) {
      acc.push(head);
      ++index;
      continue;
    }

    if (head <= 127) {
      return {acc, restIndex: index, asciiLetters, scriptSet, special};
    }

    const headClass = classOf(head);

    if (headClass === "I" || headClass === "A" || headClass === "C") {
      acc.push(head);
      scriptSet = intersect(scriptSet, scriptSetOf(head));
      asciiLetters = false;
      ++index;
      continue;
    }

    const expansion = nfcExpansion(head);

    if (expansion !== null && classOf(expansion[0]) === "I") {
      acc.push(head);
      scriptSet = intersect(scriptSet, scriptSetOf(expansion[0]));
      asciiLetters = false;
      moveToFront(special, "nfkc");
      ++index;
      continue;
    }

    return {error: "unexpected_token", acc: [...acc, head]};
  }

  return {acc, restIndex: index, asciiLetters, scriptSet, special};
};

// Mirrors validate/2.
const validate = (state, kind, codePoints) => {
  if (state.error === "unexpected_token") {
    return Type.tuple([
      Type.atom("error"),
      Type.tuple([
        Type.atom("unexpected_token"),
        Type.list(state.acc.map((codePoint) => Type.integer(codePoint))),
      ]),
    ]);
  }

  const {acc, restIndex, asciiLetters, scriptSet, special} = state;
  const length = restIndex;

  const rest = Type.list(
    codePoints.slice(restIndex).map((codePoint) => Type.integer(codePoint)),
  );

  let resultAcc = acc;
  const resultSpecial = special;

  if (!asciiLetters) {
    const original = String.fromCodePoint(...acc);
    const normalized = original.normalize("NFC");

    resultAcc = Array.from(normalized).map((c) => c.codePointAt(0));

    if (normalized !== original) {
      moveToFront(resultSpecial, "nfkc");
    }

    if (isEmpty(scriptSet) && !chunksSingle(resultAcc)) {
      const explanation = resultAcc
        .map((codePoint) => {
          const hex = codePoint.toString(16).toUpperCase().padStart(4, "0");
          return `  \\u${hex} ${String.fromCodePoint(codePoint)}\n`;
        })
        .join("");

      const suffix =
        "\n\nMixed-script identifiers are not supported for security reasons. " +
        `'${String.fromCodePoint(...resultAcc)}' is made of the following scripts:\n\n` +
        explanation +
        "\nCharacters in identifiers from different scripts must be separated by underscore (_).\n";

      return Type.tuple([
        Type.atom("error"),
        Type.tuple([
          Type.atom("mixed_script"),
          Type.list(resultAcc.map((codePoint) => Type.integer(codePoint))),
          Type.tuple([
            Type.charlist("invalid mixed-script identifier found: "),
            Type.charlist(suffix),
          ]),
        ]),
      ]);
    }
  }

  return Type.tuple([
    Type.atom(kind),
    Type.list(resultAcc.map((codePoint) => Type.integer(codePoint))),
    rest,
    Type.integer(length),
    Type.boolean(asciiLetters),
    Type.list(resultSpecial.map((name) => Type.atom(name))),
  ]);
};

const Elixir_String_Tokenizer = {
  "tokenize/1": (subject) => {
    if (!Type.isList(subject)) {
      Interpreter.raiseFunctionClauseError("String.Tokenizer", "tokenize", 1, [
        subject,
      ]);
    }

    const codePoints = subject.data.map((term) => Number(term.value));

    if (codePoints.length === 0) {
      return Type.tuple([Type.atom("error"), Type.atom("empty")]);
    }

    const head = codePoints[0];

    let kind;
    let asciiLetters;
    let scriptSet;

    if (asciiUpper(head)) {
      kind = "alias";
      asciiLetters = true;
      scriptSet = LATIN;
    } else if (asciiLower(head)) {
      kind = "identifier";
      asciiLetters = true;
      scriptSet = LATIN;
    } else if (head === 95) {
      kind = "identifier";
      asciiLetters = true;
      scriptSet = ALL;
    } else {
      const headClass = classOf(head);

      if (headClass === "A") {
        kind = "atom";
        asciiLetters = false;
        scriptSet = scriptSetOf(head);
      } else if (headClass === "I") {
        kind = "identifier";
        asciiLetters = false;
        scriptSet = scriptSetOf(head);
      } else {
        const expansion = nfcExpansion(head);

        if (expansion !== null && classOf(expansion[0]) === "I") {
          kind = "identifier";
          asciiLetters = false;
          scriptSet = scriptSetOf(expansion[0]);
        } else {
          return Type.tuple([Type.atom("error"), Type.atom("empty")]);
        }
      }
    }

    const state = continueTokens(
      codePoints,
      1,
      [head],
      asciiLetters,
      scriptSet,
    );

    return validate(state, kind, codePoints);
  },
};

export default Elixir_String_Tokenizer;
