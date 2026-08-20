"use strict";

import {defineRuntimeGlobals} from "../../../test/javascript/support/helpers.mjs";

import Model from "../../../assets/js/model.mjs";

// What the data-layer benchmarks run against: a task nine attributes wide, two of them
// datetimes, one of them ordered by - the shape a row has on the wire, and the shape the
// client's database holds.

export const PROJECT = "MyApp.Project";
export const TASK = "MyApp.Task";

export function defineModel() {
  defineRuntimeGlobals();

  globalThis.Hologram.sync = {
    model: {
      [PROJECT]: {
        attributes: {id: "uuid", name: "string"},
        relationships: {tasks: {toMany: true, type: TASK}},
        serverOnly: [],
        sortKeys: [],
      },
      [TASK]: {
        attributes: {
          created_at: "datetime",
          done: "boolean",
          due_on: "date",
          id: "uuid",
          position: "integer",
          status: "enum",
          title: "string",
          updated_at: "datetime",
          weight: "float",
        },
        relationships: {project: {toMany: false, type: PROJECT}},
        serverOnly: ["internal_notes"],
        sortKeys: ["title"],
      },
    },
  };

  Model.reset();
}

export function fillFrame(count) {
  const rows = [];

  for (let index = 0; index < count; index++) {
    rows.push(taskRow(index));
  }

  return {put_entity: {[TASK]: rows}};
}

// A page's worth of reading: the shapes a component asks for, from the plainest filter to the
// one that orders by a string.
export function pageTerms() {
  const base = {
    cardinality: "set",
    entity: TASK,
    filter: [],
    include: {},
    limit: null,
    offset: null,
    orderBy: [["id", "asc"]],
  };

  return [
    {...base, filter: [["status", "==", "open"]]},
    {
      ...base,
      filter: [["done", "==", false]],
      limit: 50,
      orderBy: [
        ["title", "asc"],
        ["id", "asc"],
      ],
    },
    {...base, filter: [["position", ">=", 50]], limit: 20},
    {...base, cardinality: "count", filter: [["status", "==", "closed"]]},
    {...base, cardinality: "one", filter: [["id", "==", "t1234"]]},
  ];
}

export function patchFrame(count) {
  const rows = [];

  for (let index = 0; index < count; index++) {
    rows.push({id: `t${index}`, title: `Renamed task ${index}`});
  }

  return {patch_entity: {[TASK]: rows}};
}

export function taskRow(index) {
  return {
    created_at: "2026-08-16T15:18:13.022508Z",
    done: index % 3 === 0,
    due_on: "2026-08-16",
    id: `t${index}`,
    position: index % 97,
    project_id: `p${index % 50}`,
    status: index % 2 === 0 ? "open" : "closed",
    title: `Task number ${index} of the fill`,
    updated_at: "2026-08-16T15:18:13.022508Z",
    weight: (index % 40) / 4,
  };
}
