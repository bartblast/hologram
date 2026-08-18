"use strict";

import {assert} from "./support/helpers.mjs";

import LocalDatabase from "../../assets/js/local_database.mjs";

describe("LocalDatabase", () => {
  beforeEach(() => {
    LocalDatabase.reset();
  });

  describe("addFact()", () => {
    it("records a pair", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1"]),
      );
    });

    it("records a repeated pair once", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1"]),
      );
    });
  });

  describe("deleteFact()", () => {
    it("removes a pair, keeping the source's other pairs", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t2");

      LocalDatabase.deleteFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t2"]),
      );
    });

    it("does nothing for a pair never recorded", () => {
      LocalDatabase.deleteFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("deleteRow()", () => {
    it("removes the row", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      LocalDatabase.deleteRow("MyApp.Task", "t1");

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    it("removes the row's relationship facts with it", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Website"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");

      LocalDatabase.deleteRow("MyApp.Project", "p1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });

    it("keeps other rows and their facts", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Website"});
      LocalDatabase.putRow("MyApp.Project", {id: "p2", name: "Launch"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p2", "t2");

      LocalDatabase.deleteRow("MyApp.Project", "p1");

      assert.deepEqual(LocalDatabase.getRow("MyApp.Project", "p2"), {
        id: "p2",
        name: "Launch",
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p2"),
        new Set(["t2"]),
      );
    });

    it("does nothing for a row never held", () => {
      LocalDatabase.deleteRow("MyApp.Task", "t1");

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });
  });

  describe("getRow()", () => {
    it("returns the held row", () => {
      const row = {id: "t1", title: "Draft copy"};
      LocalDatabase.putRow("MyApp.Task", row);

      assert.equal(LocalDatabase.getRow("MyApp.Task", "t1"), row);
    });

    it("returns null for an id not held", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t9"));
    });

    it("returns null for a type never filed", () => {
      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });
  });

  describe("getTable()", () => {
    it("returns the type's rows keyed by id", () => {
      const first = {id: "t1", title: "Draft copy"};
      const second = {id: "t2", title: "Ship it"};

      LocalDatabase.putRow("MyApp.Task", first);
      LocalDatabase.putRow("MyApp.Task", second);

      assert.deepEqual(LocalDatabase.getTable("MyApp.Task"), {
        t1: first,
        t2: second,
      });
    });

    it("returns an empty table for a type never filed", () => {
      assert.deepEqual(LocalDatabase.getTable("MyApp.Task"), {});
    });
  });

  describe("getTargetIds()", () => {
    it("returns the source's pair targets", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t2");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1", "t2"]),
      );
    });

    it("returns an empty set for a source never recorded", () => {
      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("isSynced()", () => {
    it("answers false before the scope's marker arrived", () => {
      assert.isFalse(LocalDatabase.isSynced("page"));
    });

    it("answers true once the scope is marked", () => {
      LocalDatabase.markSynced("page");

      assert.isTrue(LocalDatabase.isSynced("page"));
    });

    it("marks each scope on its own", () => {
      LocalDatabase.markSynced("page");

      assert.isFalse(LocalDatabase.isSynced("all"));
    });
  });

  describe("markSynced()", () => {
    // What a page still carries when the whole pot declares itself complete was never this
    // client's to hold - a grant revoked between the render and the connect leaves exactly that.
    it("drops a carried row the fill never delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markSynced("all");

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps a carried row the fill delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Task", "t1");

      LocalDatabase.markSynced("all");

      assert.deepEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });
    });

    it("keeps a row no page carried", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      LocalDatabase.markSynced("all");

      assert.deepEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });
    });

    // The page scope says one page's rows are complete, which says nothing about a row another
    // page carried - only the whole pot's marker can call one an orphan.
    it("sweeps nothing at the page scope", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markSynced("page");

      assert.deepEqual(LocalDatabase.carriedEntries(), [["MyApp.Task", "t1"]]);
      assert.isNotNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    // A swept row takes its relationship facts with it, the way any row leaving the pot does.
    it("takes the swept row's relationship facts with it", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Board"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.markCarried("MyApp.Project", "p1");

      LocalDatabase.markSynced("all");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("putRow()", () => {
    it("files the row under its id", () => {
      const row = {id: "t1", title: "Draft copy"};

      LocalDatabase.putRow("MyApp.Task", row);

      assert.equal(LocalDatabase.getRow("MyApp.Task", "t1"), row);
    });

    it("replaces the row already held under the id", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      const fresher = {id: "t1", title: "Ship it"};
      LocalDatabase.putRow("MyApp.Task", fresher);

      assert.equal(LocalDatabase.getRow("MyApp.Task", "t1"), fresher);
    });
  });

  describe("replaceFacts()", () => {
    it("records the whole target set", () => {
      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t1", "t2"]);

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1", "t2"]),
      );
    });

    it("drops pairs the new set no longer holds", () => {
      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t1", "t2"]);

      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t2", "t3"]);

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t2", "t3"]),
      );
    });

    it("records an empty set as truly empty", () => {
      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t1"]);

      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", []);

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("carriedEntries()", () => {
    it("returns the rows marked as arrived with a page", () => {
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.markCarried("MyApp.Project", "p1");

      assert.sameDeepMembers(LocalDatabase.carriedEntries(), [
        ["MyApp.Task", "t1"],
        ["MyApp.Project", "p1"],
      ]);
    });

    it("returns nothing once a row is unmarked", () => {
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Task", "t1");

      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("marks a row of one type without marking the same id of another", () => {
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Project", "t1");

      assert.deepEqual(LocalDatabase.carriedEntries(), [["MyApp.Task", "t1"]]);
    });
  });

  describe("reset()", () => {
    it("drops the rows, the facts, the scope marks and what a page carried", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.markSynced("page");

      LocalDatabase.reset();

      assert.deepEqual(LocalDatabase.carriedEntries(), []);

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );

      assert.isFalse(LocalDatabase.isSynced("page"));
    });
  });
});
