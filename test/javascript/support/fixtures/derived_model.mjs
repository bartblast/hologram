"use strict";

// The data model the build bakes for the Elixir suite's derived-field fixtures, trimmed to the keys
// the kernel reads, under the names the kernel suite uses: Hologram.Test.Fixtures.Entity.Module1 is
// MyApp.Author, Module2 MyApp.Tag, Module32 MyApp.Channel, Module33 MyApp.Message, Module34
// MyApp.Member, Module37 MyApp.Room, Module38 MyApp.Post, Module39 MyApp.Player, Module40 MyApp.Team
// and Module41 MyApp.Note. Rendered by Hologram.Compiler.build_sync_constants_js/1, so the kernel
// computes from the definitions the interpreter suite computes from - regenerate it when one of
// those fixtures changes.
export default {
  "MyApp.Author": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      updated_at: "datetime",
    },
    derived: {},
    enumValues: {},
    inverses: {},
    relationships: {},
    serverOnly: [],
  },
  "MyApp.Channel": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      name: "string",
      updated_at: "datetime",
    },
    derived: {
      first_message: {
        definition: {
          query: {
            cardinality: "one",
            entity: "MyApp.Message",
            filter: [],
            include: {},
            skip: null,
            sort: [
              ["position", "asc"],
              ["id", "asc"],
            ],
            source: {
              chain: ["messages"],
              owner: "MyApp.Channel",
            },
            take: null,
          },
        },
        entity: "MyApp.Message",
        kind: "one",
      },
      first_messages: {
        definition: {
          query: {
            cardinality: "set",
            entity: "MyApp.Message",
            filter: [],
            include: {},
            skip: null,
            sort: [
              ["position", "asc"],
              ["id", "asc"],
            ],
            source: {
              chain: ["messages"],
              owner: "MyApp.Channel",
            },
            take: 3,
          },
        },
        entity: "MyApp.Message",
        kind: "set",
      },
      message_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Message",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["messages"],
              owner: "MyApp.Channel",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      recent_messages: {
        definition: {
          query: {
            cardinality: "set",
            entity: "MyApp.Message",
            filter: [],
            include: {},
            skip: null,
            sort: [
              ["position", "desc"],
              ["id", "asc"],
            ],
            source: {
              chain: ["messages"],
              owner: "MyApp.Channel",
            },
            take: 2,
          },
        },
        entity: "MyApp.Message",
        kind: "set",
      },
    },
    enumValues: {},
    inverses: {
      messages: {
        forward: "channel",
        reference: true,
        sort: [["position", "asc"]],
        toMany: true,
        type: "MyApp.Message",
      },
    },
    relationships: {},
    serverOnly: [],
  },
  "MyApp.Member": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      nickname: "string",
      score: "integer",
      updated_at: "datetime",
    },
    derived: {
      active: {
        definition: {
          condition: [
            ["score", ">", 0],
            ["score", "<", 3],
          ],
        },
        kind: "scalar",
        type: "boolean",
        values: null,
      },
      badge: {
        definition: {
          else: {
            value: null,
          },
          if: [["score", ">=", 3]],
          then: {
            value: "top",
          },
        },
        kind: "scalar",
        type: "string",
        values: null,
      },
      channel_load: {
        definition: {
          name: ["channel", "message_count"],
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      display_name: {
        definition: {
          concat: [
            {
              name: "nickname",
            },
            {
              value: " (",
            },
            {
              name: ["channel", "name"],
            },
            {
              value: ")",
            },
          ],
        },
        kind: "scalar",
        type: "string",
        values: null,
      },
      featured: {
        definition: {
          condition: [
            {
              or: [[["score", "not_in", [0]]], [["nickname", "==", "lead"]]],
            },
          ],
        },
        kind: "scalar",
        type: "boolean",
        values: null,
      },
      level: {
        definition: {
          else: {
            value: "quiet",
          },
          if: [["channel_load", ">", 3]],
          then: {
            value: "busy",
          },
        },
        kind: "scalar",
        type: "enum",
        values: ["busy", "quiet"],
      },
      named_after_channel: {
        definition: {
          condition: [
            [
              "nickname",
              "==",
              {
                attribute: ["channel", "name"],
              },
            ],
          ],
        },
        kind: "scalar",
        type: "boolean",
        values: null,
      },
      ranked: {
        definition: {
          condition: [
            {
              or: [
                [["score", "in", [1, 2]]],
                [
                  [["channel", "name"], "in", ["general"]],
                  ["score", ">", -1],
                ],
              ],
            },
          ],
        },
        kind: "scalar",
        type: "boolean",
        values: null,
      },
      recent_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Message",
            filter: [["position", ">", 1]],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["channel", "messages"],
              owner: "MyApp.Member",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      score_label: {
        definition: {
          else: {
            value: "low",
          },
          if: [["score", ">", 5]],
          then: {
            value: "high",
          },
        },
        kind: "scalar",
        type: "string",
        values: null,
      },
      top_score: {
        definition: {
          value: 10,
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
    },
    enumValues: {},
    inverses: {},
    relationships: {
      channel: {
        optional: true,
        toMany: false,
        type: "MyApp.Channel",
      },
    },
    serverOnly: [],
  },
  "MyApp.Message": {
    attributes: {
      body: "string",
      created_at: "datetime",
      id: "uuid",
      position: "integer",
      updated_at: "datetime",
    },
    derived: {
      channel_name: {
        definition: {
          name: ["channel", "name"],
        },
        kind: "scalar",
        type: "string",
        values: null,
      },
      later_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Message",
            filter: [
              [
                "position",
                ">",
                {
                  attribute: {
                    name: "position",
                    outer: 1,
                  },
                },
              ],
            ],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["channel", "messages"],
              owner: "MyApp.Message",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      tier: {
        definition: {
          value: "low",
        },
        kind: "scalar",
        type: "enum",
        values: ["low", "high"],
      },
    },
    enumValues: {},
    inverses: {},
    relationships: {
      channel: {
        optional: true,
        toMany: false,
        type: "MyApp.Channel",
      },
    },
    serverOnly: [],
  },
  "MyApp.Note": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      public: "boolean",
      updated_at: "datetime",
    },
    derived: {},
    enumValues: {},
    inverses: {},
    relationships: {
      tags: {
        optional: false,
        toMany: true,
        type: "MyApp.Tag",
      },
      team: {
        optional: true,
        toMany: false,
        type: "MyApp.Team",
      },
    },
    serverOnly: [],
  },
  "MyApp.Player": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      kind: "enum",
      score: "integer",
      updated_at: "datetime",
    },
    derived: {
      gold: {
        definition: {
          condition: [["tier", "==", "gold"]],
        },
        kind: "scalar",
        type: "boolean",
        values: null,
      },
      kind_label: {
        definition: {
          name: "kind",
        },
        kind: "scalar",
        type: "enum",
        values: ["guest", "staff"],
      },
      member_name: {
        definition: {
          name: ["member", "display_name"],
        },
        kind: "scalar",
        type: "string",
        values: null,
      },
      ratio: {
        definition: {
          name: "score",
        },
        kind: "scalar",
        type: "float",
        values: null,
      },
      tier: {
        definition: {
          else: {
            else: {
              value: "bronze",
            },
            if: [["score", ">", 5]],
            then: {
              value: "silver",
            },
          },
          if: [["score", ">", 10]],
          then: {
            value: "gold",
          },
        },
        kind: "scalar",
        type: "enum",
        values: ["gold", "silver", "bronze"],
      },
    },
    enumValues: {
      kind: ["guest", "staff"],
    },
    inverses: {},
    relationships: {
      member: {
        optional: true,
        toMany: false,
        type: "MyApp.Member",
      },
      mentors: {
        optional: false,
        toMany: true,
        type: "MyApp.Member",
      },
    },
    serverOnly: [],
  },
  "MyApp.Post": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      pinned: "boolean",
      updated_at: "datetime",
    },
    derived: {
      sibling_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Post",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["channel", "messages"],
              owner: "MyApp.Post",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
    },
    enumValues: {},
    inverses: {},
    relationships: {
      author: {
        optional: true,
        toMany: false,
        type: "MyApp.Author",
      },
      channel: {
        optional: false,
        toMany: false,
        type: "MyApp.Room",
      },
    },
    serverOnly: [],
  },
  "MyApp.Room": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      last_read_at: "datetime",
      name: "string",
      updated_at: "datetime",
    },
    derived: {
      authored_messages: {
        definition: {
          query: {
            cardinality: "set",
            entity: "MyApp.Post",
            filter: [],
            include: {
              author: {
                cardinality: "set",
                entity: "MyApp.Author",
                filter: [],
                include: {},
                skip: null,
                sort: [],
                take: null,
              },
            },
            skip: null,
            sort: [["id", "asc"]],
            source: {
              chain: ["messages"],
              owner: "MyApp.Room",
            },
            take: null,
          },
        },
        entity: "MyApp.Post",
        kind: "set",
      },
      busy: {
        definition: {
          condition: [["pinned_count", ">", 3]],
        },
        kind: "scalar",
        type: "boolean",
        values: null,
      },
      colleague_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Post",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["messages", "channel", "messages"],
              owner: "MyApp.Room",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      member_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Tag",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["members"],
              owner: "MyApp.Room",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      nothing: {
        definition: {
          value: null,
        },
        entity: "MyApp.Post",
        kind: "set",
      },
      picked: {
        definition: {
          else: {
            query: {
              cardinality: "set",
              entity: "MyApp.Post",
              filter: [],
              include: {},
              skip: null,
              sort: [["id", "asc"]],
              source: {
                chain: ["messages", "channel", "messages"],
                owner: "MyApp.Room",
              },
              take: null,
            },
          },
          if: [["name", "==", "general"]],
          then: {
            query: {
              cardinality: "set",
              entity: "MyApp.Post",
              filter: [],
              include: {},
              skip: null,
              sort: [["id", "asc"]],
              source: {
                chain: ["messages"],
                owner: "MyApp.Room",
              },
              take: 1,
            },
          },
        },
        entity: "MyApp.Post",
        kind: "set",
      },
      picked_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Post",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["picked"],
              owner: "MyApp.Room",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      pinned_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Post",
            filter: [["pinned", "==", true]],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["messages"],
              owner: "MyApp.Room",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      recent_messages: {
        definition: {
          query: {
            cardinality: "set",
            entity: "MyApp.Post",
            filter: [],
            include: {},
            skip: null,
            sort: [
              ["created_at", "desc"],
              ["id", "asc"],
            ],
            source: {
              chain: ["messages"],
              owner: "MyApp.Room",
            },
            take: 3,
          },
        },
        entity: "MyApp.Post",
        kind: "set",
      },
      unread_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Post",
            filter: [
              [
                "created_at",
                ">",
                {
                  attribute: {
                    name: "last_read_at",
                    outer: 1,
                  },
                },
              ],
            ],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["messages"],
              owner: "MyApp.Room",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
    },
    enumValues: {},
    inverses: {
      messages: {
        forward: "channel",
        reference: true,
        sort: [],
        toMany: true,
        type: "MyApp.Post",
      },
    },
    relationships: {
      members: {
        optional: false,
        toMany: true,
        type: "MyApp.Tag",
      },
    },
    serverOnly: [],
  },
  "MyApp.Tag": {
    attributes: {
      a: "boolean",
      b: "integer",
      c: "string",
      created_at: "datetime",
      id: "uuid",
      updated_at: "datetime",
    },
    derived: {},
    enumValues: {},
    inverses: {},
    relationships: {},
    serverOnly: [],
  },
  "MyApp.Team": {
    attributes: {
      created_at: "datetime",
      id: "uuid",
      name: "string",
      updated_at: "datetime",
    },
    derived: {
      capped_note_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Note",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["notes"],
              owner: "MyApp.Team",
            },
            take: 2,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      mentor_message_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Message",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["mentors", "channel", "messages"],
              owner: "MyApp.Team",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      named_tag_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Note",
            filter: [
              {
                filter: [
                  [
                    "c",
                    "==",
                    {
                      attribute: {
                        name: "name",
                        outer: 2,
                      },
                    },
                  ],
                ],
                quantifier: "any",
                source: ["tags"],
              },
            ],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["notes"],
              owner: "MyApp.Team",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      no_note: {
        definition: {
          value: null,
        },
        entity: "MyApp.Note",
        kind: "one",
      },
      note_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Note",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["notes"],
              owner: "MyApp.Team",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      note_tag_count: {
        definition: {
          query: {
            cardinality: "count",
            entity: "MyApp.Tag",
            filter: [],
            include: {},
            skip: null,
            sort: [],
            source: {
              chain: ["notes", "tags"],
              owner: "MyApp.Team",
            },
            take: null,
          },
        },
        kind: "scalar",
        type: "integer",
        values: null,
      },
      picked_notes: {
        definition: {
          else: {
            query: {
              cardinality: "set",
              entity: "MyApp.Note",
              filter: [],
              include: {
                team: {
                  cardinality: "set",
                  entity: "MyApp.Team",
                  filter: [],
                  include: {},
                  skip: null,
                  sort: [],
                  take: null,
                },
              },
              skip: null,
              sort: [["id", "asc"]],
              source: {
                chain: ["notes"],
                owner: "MyApp.Team",
              },
              take: null,
            },
          },
          if: [["name", "==", "tagged"]],
          then: {
            query: {
              cardinality: "set",
              entity: "MyApp.Note",
              filter: [],
              include: {
                tags: {
                  cardinality: "set",
                  entity: "MyApp.Tag",
                  filter: [],
                  include: {},
                  skip: null,
                  sort: [["id", "asc"]],
                  take: null,
                },
              },
              skip: null,
              sort: [["id", "asc"]],
              source: {
                chain: ["notes"],
                owner: "MyApp.Team",
              },
              take: null,
            },
          },
        },
        entity: "MyApp.Note",
        kind: "set",
      },
      second_note: {
        definition: {
          query: {
            cardinality: "one",
            entity: "MyApp.Note",
            filter: [],
            include: {},
            skip: 1,
            sort: [["id", "asc"]],
            source: {
              chain: ["notes"],
              owner: "MyApp.Team",
            },
            take: null,
          },
        },
        entity: "MyApp.Note",
        kind: "one",
      },
    },
    enumValues: {},
    inverses: {
      notes: {
        forward: "team",
        reference: true,
        sort: [],
        toMany: true,
        type: "MyApp.Note",
      },
    },
    relationships: {
      mentors: {
        optional: false,
        toMany: true,
        type: "MyApp.Member",
      },
      players: {
        optional: false,
        toMany: true,
        type: "MyApp.Player",
      },
    },
    serverOnly: [],
  },
};
