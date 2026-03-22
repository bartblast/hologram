"use strict";

const Erlang_Fixture = {
  // Start no_comments/1
  "no_comments/1": (x) => {
    return x;
  },
  // End no_comments/1
  // Deps: []

  // Start single_comment/0
  // This function has a single comment line.
  "single_comment/0": () => {
    return 1;
  },
  // End single_comment/0
  // Deps: []

  // Start multiple_comments/2
  // First comment line.
  // Second comment line.
  "multiple_comments/2": (a, b) => {
    return a + b;
  },
  // End multiple_comments/2
  // Deps: []

  // Start not_implemented/0
  // End not_implemented/0
};

export default Erlang_Fixture;
