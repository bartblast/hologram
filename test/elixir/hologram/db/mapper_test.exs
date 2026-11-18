defmodule Hologram.DB.MapperTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Mapper

  alias Hologram.Auth.RoleGrant
  alias Hologram.Entity.Model
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Role

  defp column(entity_type, name) do
    entity_type
    |> columns()
    |> Enum.find(&(&1.name == name))
  end

  describe "columns/1" do
    test "derives only system columns for entity type with no declarations" do
      assert columns(Module1) == [
               %{
                 name: "id",
                 type: :uuid,
                 sql_type: "uuid",
                 collation: nil,
                 enum_values: nil,
                 default: nil,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 source: :system
               },
               %{
                 name: "created_at",
                 type: :datetime,
                 sql_type: "timestamptz",
                 collation: nil,
                 enum_values: nil,
                 default: nil,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 source: :system
               },
               %{
                 name: "updated_at",
                 type: :datetime,
                 sql_type: "timestamptz",
                 collation: nil,
                 enum_values: nil,
                 default: nil,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 source: :system
               },
               %{
                 name: "$revisions",
                 type: :map,
                 sql_type: "jsonb",
                 collation: nil,
                 enum_values: nil,
                 default: %{},
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 source: :revisions
               }
             ]
    end

    test "derives the revisions column for every entity type" do
      revisions_columns =
        Module2
        |> columns()
        |> Enum.filter(&(&1.source == :revisions))

      assert revisions_columns == [
               %{
                 name: "$revisions",
                 type: :map,
                 sql_type: "jsonb",
                 collation: nil,
                 enum_values: nil,
                 default: %{},
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 source: :revisions
               }
             ]
    end

    test "derives attribute columns sorted by name, nullable only when optional" do
      attribute_columns =
        Module2
        |> columns()
        |> Enum.filter(&match?({:attribute, _name}, &1.source))

      assert attribute_columns == [
               %{
                 name: "a",
                 type: :boolean,
                 sql_type: "boolean",
                 collation: nil,
                 enum_values: nil,
                 default: false,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 source: {:attribute, :a}
               },
               %{
                 name: "b",
                 type: :integer,
                 sql_type: "int8",
                 collation: nil,
                 enum_values: nil,
                 default: nil,
                 null: true,
                 references: nil,
                 fk_constraint: nil,
                 source: {:attribute, :b}
               },
               %{
                 name: "c",
                 type: :string,
                 sql_type: "text",
                 collation: "C",
                 enum_values: nil,
                 default: nil,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 source: {:attribute, :c}
               }
             ]
    end

    test "maps :boolean to boolean" do
      assert column(Module2, "a").sql_type == "boolean"
    end

    test "maps :date to date" do
      assert column(Module4, "a").sql_type == "date"
    end

    test "maps :datetime to timestamptz" do
      assert column(Module4, "b").sql_type == "timestamptz"
    end

    test "maps :enum to a derived per-attribute native enum type" do
      assert column(Module4, "c").sql_type == "test_fixtures_entity_module4_c_$enum"
    end

    test "maps :float to float8" do
      assert column(Module4, "d").sql_type == "float8"
    end

    test "maps :integer to int8" do
      assert column(Module2, "b").sql_type == "int8"
    end

    test "maps :string to text with pinned C collation" do
      assert column(Module2, "c").sql_type == "text"
      assert column(Module2, "c").collation == "C"
    end

    test "maps :time to time" do
      defmodule InlineEntityFixture22 do
        use Hologram.Entity

        attribute :opens_at, :time, optional: true
      end

      assert column(InlineEntityFixture22, "opens_at").sql_type == "time"
    end

    test "maps :uuid to uuid" do
      defmodule InlineEntityFixture19 do
        use Hologram.Entity

        attribute :external_id, :uuid, optional: true
      end

      assert column(InlineEntityFixture19, "external_id") == %{
               name: "external_id",
               type: :uuid,
               sql_type: "uuid",
               collation: nil,
               enum_values: nil,
               default: nil,
               null: true,
               references: nil,
               fk_constraint: nil,
               source: {:attribute, :external_id}
             }
    end

    test "derives nil collation for types that carry none" do
      assert column(Module2, "a").collation == nil
    end

    test "carries enum values as strings in declaration order" do
      assert column(Module4, "c").enum_values == ["x", "y"]
    end

    test "carries enum values that are modules without their Elixir prefix" do
      assert "Hologram.Test.Fixtures.Role.Module1" in column(Hologram.Auth.RoleGrant, "role").enum_values
    end

    test "carries the declared default value" do
      assert column(Module4, "c").default == :x
    end

    test "derives nil default for attributes without one" do
      assert column(Module4, "a").default == nil
    end

    test "derives nil enum values for non-enum types" do
      assert column(Module4, "a").enum_values == nil
    end

    test "derives a sort-key companion column for every string attribute" do
      companion =
        Module2
        |> columns()
        |> Enum.find(&(&1.source == {:sort_key, :c}))

      assert companion == %{
               name: "c_$sort",
               type: :string,
               sql_type: "text",
               collation: "C",
               enum_values: nil,
               default: nil,
               null: true,
               references: nil,
               fk_constraint: nil,
               source: {:sort_key, :c}
             }
    end

    test "derives a search-key companion column for every string attribute" do
      companion =
        Module2
        |> columns()
        |> List.last()

      assert companion == %{
               name: "c_$search",
               type: :string,
               sql_type: "text",
               collation: "C",
               enum_values: nil,
               default: nil,
               null: true,
               references: nil,
               fk_constraint: nil,
               source: {:search_key, :c}
             }
    end

    test "derives the companions in attribute-name order, server-only attributes included" do
      sources =
        Module15
        |> columns()
        |> Enum.take(-6)
        |> Enum.map(& &1.source)

      assert sources == [
               {:sort_key, :label},
               {:sort_key, :secret_note},
               {:sort_key, :token},
               {:search_key, :label},
               {:search_key, :secret_note},
               {:search_key, :token}
             ]
    end

    test "derives to-one relationship reference columns and excludes to-many relationships" do
      relationship_columns =
        Module3
        |> columns()
        |> Enum.filter(&match?({:relationship, _name}, &1.source))

      assert relationship_columns == [
               %{
                 name: "b_id",
                 type: :uuid,
                 sql_type: "uuid",
                 collation: nil,
                 enum_values: nil,
                 default: nil,
                 null: true,
                 references: "test_fixtures_entity_module2",
                 fk_constraint: "test_fixtures_entity_module3_b_id_$fk",
                 source: {:relationship, :b}
               },
               %{
                 name: "c_id",
                 type: :uuid,
                 sql_type: "uuid",
                 collation: nil,
                 enum_values: nil,
                 default: nil,
                 null: false,
                 references: "test_fixtures_entity_module1",
                 fk_constraint: "test_fixtures_entity_module3_c_id_$fk",
                 source: {:relationship, :c}
               }
             ]
    end

    test "shortens foreign key constraint names over the PostgreSQL identifier limit, keeping the kind" do
      defmodule InlineEntityFixture17 do
        use Hologram.Entity

        relationship :quite_long_relationship_name, Module1
      end

      assert column(InlineEntityFixture17, "quite_long_relationship_name_id").fk_constraint ==
               "quite_long_relationship_name_id_bbbac617_$fk"
    end

    test "rejects declarations deriving the same column name" do
      # Bare reflection functions instead of use Hologram.Entity - the entity
      # validator now rejects this collision at declaration time, and the
      # mapper's own check guards the standalone mapper API contract.
      defmodule InlineEntityFixture1 do
        @spec __attributes__() :: list(tuple)
        def __attributes__, do: [{:project_id, :string, []}]

        @spec __relationships__() :: list(tuple)
        def __relationships__, do: [{:project, Hologram.Test.Fixtures.Entity.Module1, []}]
      end

      expected_msg =
        normalize_newlines("""
        colliding column names in Hologram.DB.MapperTest.InlineEntityFixture1 - rename the declarations so that every derived column name is unique:
          * column "project_id" is derived from attribute :project_id, relationship :project\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        columns(InlineEntityFixture1)
      end
    end

    # The entity validator refuses a declared name carrying the $ seam, so the DSL cannot reach
    # this - but a module writing the reflection functions by hand never meets the validator, and
    # the grant store is one such module. The framework's own side of the collision has no
    # declaration to name, which is what the message has to survive saying.
    test "rejects a declaration deriving a column name the framework owns" do
      defmodule InlineEntityFixture21 do
        @spec __attributes__() :: list(tuple)
        def __attributes__, do: [{:"$revisions", :string, []}]

        @spec __relationships__() :: list(tuple)
        def __relationships__, do: []
      end

      expected_msg =
        normalize_newlines("""
        colliding column names in Hologram.DB.MapperTest.InlineEntityFixture21 - rename the declarations so that every derived column name is unique:
          * column "$revisions" is derived from attribute :"$revisions", the framework\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        columns(InlineEntityFixture21)
      end
    end
  end

  describe "data_schema/0" do
    test "returns the schema of the entity tables" do
      assert data_schema() == "hologram_data"
    end
  end

  describe "derive!/2" do
    test "derives the role grant store's unique index comparing nulls as values" do
      mapping =
        derive!(
          [
            Hologram.Auth.RoleGrant,
            Hologram.Test.Fixtures.Entity.Module14,
            Module1
          ],
          []
        )

      assert mapping[Hologram.Auth.RoleGrant].indexes == %{
               "hologram_role_grant_user_id_entity_type_entity_id_role_$uidx" => %{
                 columns: ["user_id", "entity_type", "entity_id", "role"],
                 nulls_distinct: false,
                 unique: true
               }
             }
    end

    test "derives a unique index per unique attribute" do
      mapping = derive!([Module19], [])

      assert mapping[Module19].indexes == %{
               "test_fixtures_entity_module19_code_$uidx" => %{
                 columns: ["code"],
                 nulls_distinct: true,
                 unique: true
               },
               "test_fixtures_entity_module19_slug_$uidx" => %{
                 columns: ["slug"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "derives no index for an attribute that is not unique" do
      mapping = derive!([Module2], [])

      assert mapping[Module2].indexes == %{}
    end

    test "derives a unique index over a unique to-one's reference column" do
      mapping = derive!([Module26, Module27], [])

      assert mapping[Module27].indexes == %{
               "test_fixtures_entity_module27_channel_id_$uidx" => %{
                 columns: ["channel_id"],
                 nulls_distinct: true,
                 unique: true
               },
               "test_fixtures_entity_module27_code_$uidx" => %{
                 columns: ["code"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "derives no unique index for a to-one that is not unique" do
      mapping = derive!([Module1, Module2, Module3], [])

      assert mapping[Module3].indexes == %{}
    end

    test "derives no column and no join table for an inverse relationship" do
      mapping = derive!([Module26, Module27, Module28, Module29], [])

      assert Enum.map(mapping[Module26].columns, & &1.source) == [
               :system,
               {:attribute, :name},
               :system,
               :system,
               :revisions,
               {:sort_key, :name},
               {:search_key, :name}
             ]

      assert mapping[Module26].join_tables == []
      assert mapping[Module29].join_tables == []
    end

    test "carries the derived companions for every string attribute" do
      mapping = derive!([Module2], [])

      sources =
        mapping[Module2].columns
        |> Enum.take(-2)
        |> Enum.map(& &1.source)

      assert sources == [{:sort_key, :c}, {:search_key, :c}]
    end

    test "derives the role grant store alongside the app's user entity type" do
      mapping = derive!([Module1, Module14], [])

      assert mapping[RoleGrant].table == "hologram_role_grant"
    end

    test "derives the role grant store's role values from the given global role modules" do
      mapping = derive!([Module1, Module14], [Role.Module2, Role.Module1])

      role_column = Enum.find(mapping[RoleGrant].columns, &(&1.source == {:attribute, :role}))

      assert role_column.enum_values == [
               "Hologram.Test.Fixtures.Role.Module1",
               "Hologram.Test.Fixtures.Role.Module2"
             ]
    end

    test "derives no role grant store for a model without the user entity type" do
      mapping = derive!([Module1], [])

      assert Map.has_key?(mapping, RoleGrant) == false
    end

    test "returns the mapping keyed by entity type" do
      mapping =
        [Module1, Module3]
        |> derive!([])
        |> Map.drop([RoleGrant])

      assert mapping == %{
               Module1 => %{
                 table: table_name(Module1),
                 pk_constraint: "test_fixtures_entity_module1_$pk",
                 columns: columns(Module1),
                 indexes: %{},
                 join_tables: join_tables(Module1)
               },
               Module3 => %{
                 table: table_name(Module3),
                 pk_constraint: "test_fixtures_entity_module3_$pk",
                 columns: columns(Module3),
                 indexes: %{},
                 join_tables: join_tables(Module3)
               }
             }
    end

    test "runs the table name collision check" do
      expected_msg =
        normalize_newlines("""
        colliding table names - rename modules so that every entity type derives a unique table name:
          * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([Hologram.Blog.Post, Hologram.BlogPost], [])
      end
    end

    test "runs the required to-one cycle check" do
      defmodule InlineEntityFixture13 do
        use Hologram.Entity

        relationship :parent, __MODULE__
      end

      expected_msg =
        normalize_newlines("""
        cyclic required to-one relationships - no row in such a cycle can ever be created, mark at least one relationship in each cycle as optional: true:
          * Hologram.DB.MapperTest.InlineEntityFixture13 (relationship :parent) -> Hologram.DB.MapperTest.InlineEntityFixture13\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([InlineEntityFixture13], [])
      end
    end

    test "rejects entities deriving the same join table name" do
      defmodule InlineEntityFixture14 do
        use Hologram.Entity

        relationship :b_c, [Module1]
      end

      defmodule InlineEntityFixture14B do
        use Hologram.Entity

        relationship :c, [Module1]
      end

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * join table "db_mapper_test_inline_entity_fixture14_b_c_$join" is derived from relationship :b_c in Hologram.DB.MapperTest.InlineEntityFixture14, relationship :c in Hologram.DB.MapperTest.InlineEntityFixture14B\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([InlineEntityFixture14, InlineEntityFixture14B], [])
      end
    end

    test "rejects entities deriving the same name for a unique attribute index" do
      defmodule InlineEntityFixture25 do
        use Hologram.Entity

        attribute :b_c, :integer, unique: true
      end

      defmodule InlineEntityFixture25B do
        use Hologram.Entity

        attribute :c, :integer, unique: true
      end

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * index "db_mapper_test_inline_entity_fixture25_b_c_$uidx" is derived from attribute :b_c in Hologram.DB.MapperTest.InlineEntityFixture25, attribute :c in Hologram.DB.MapperTest.InlineEntityFixture25B\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([InlineEntityFixture25, InlineEntityFixture25B], [])
      end
    end

    test "rejects an entity deriving the role grant store's index name" do
      defmodule Elixir.HologramRole do
        use Hologram.Entity

        attribute :grant_user_id_entity_type_entity_id_role, :integer, unique: true
      end

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * index "hologram_role_grant_user_id_entity_type_entity_id_role_$uidx" is derived from attribute :grant_user_id_entity_type_entity_id_role in HologramRole, the role grant store\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([Module14, HologramRole], [])
      end
    end

    test "rejects entities deriving the same enum type name" do
      defmodule InlineEntityFixture15 do
        use Hologram.Entity

        attribute :b_p, :enum, values: [:x, :y]
      end

      defmodule InlineEntityFixture15B do
        use Hologram.Entity

        attribute :p, :enum, values: [:x, :y]
      end

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * enum type "db_mapper_test_inline_entity_fixture15_b_p_$enum" is derived from attribute :b_p in Hologram.DB.MapperTest.InlineEntityFixture15, attribute :p in Hologram.DB.MapperTest.InlineEntityFixture15B\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([InlineEntityFixture15, InlineEntityFixture15B], [])
      end
    end

    test "lists every derived name collision across kinds" do
      defmodule InlineEntityFixture16 do
        use Hologram.Entity

        attribute :b_p, :enum, values: [:x, :y]

        relationship :b_r, [Module1]
      end

      defmodule InlineEntityFixture16B do
        use Hologram.Entity

        attribute :p, :enum, values: [:x, :y]

        relationship :r, [Module1]
      end

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * enum type "db_mapper_test_inline_entity_fixture16_b_p_$enum" is derived from attribute :b_p in Hologram.DB.MapperTest.InlineEntityFixture16, attribute :p in Hologram.DB.MapperTest.InlineEntityFixture16B
          * join table "db_mapper_test_inline_entity_fixture16_b_r_$join" is derived from relationship :b_r in Hologram.DB.MapperTest.InlineEntityFixture16, relationship :r in Hologram.DB.MapperTest.InlineEntityFixture16B\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([InlineEntityFixture16, InlineEntityFixture16B], [])
      end
    end
  end

  describe "derive_from_model!/1" do
    # Four join tables in two colliding pairs, one line each.
    test "reports two colliding join table pairs" do
      r = String.duplicate("r", 37)

      relationships = [
        {Pppppppppppppp, :xx_yy_zz_rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr},
        {Pppppppppppppp.XxYyZz, :rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr},
        {PpppppppppppppXx, :yy_zz_rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr},
        {PpppppppppppppXx.Yy, :zz_rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr}
      ]

      model = %{
        entities:
          Map.new(relationships, fn {entity_type, relationship} ->
            {entity_type,
             %{
               attributes: [],
               relationships: [{relationship, [entity_type], []}],
               roles: [],
               uniques: []
             }}
          end),
        roles: %{},
        user_entity: nil
      }

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * join table "xx_yy_zz_#{r}_7523ea5b_$join" is derived from relationship :#{r} in Pppppppppppppp.XxYyZz, relationship :xx_yy_zz_#{r} in Pppppppppppppp
          * join table "yy_zz_#{r}_7523ea5b_$join" is derived from relationship :yy_zz_#{r} in PpppppppppppppXx, relationship :zz_#{r} in PpppppppppppppXx.Yy\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> derive_from_model!(model) end
    end

    # A cut join table name keeps its relationship and a digest, which a module path can spell
    # out in full - so a join table's primary key and an entity's can meet.
    test "rejects a join table's primary key cut to an entity's primary key" do
      relationship = :a_relationship_name_longer_than_thirty_three_bytes_x1
      entity_type = :"Elixir.ARelationshipNameLongerThanThirtyThreeBytes.9e7c7fc8"

      model = %{
        entities: %{
          Nonexistent.Post => %{
            attributes: [],
            relationships: [{relationship, [Nonexistent.Post], []}],
            roles: [],
            uniques: []
          },
          entity_type => %{attributes: [], relationships: [], roles: [], uniques: []}
        },
        roles: %{},
        user_entity: nil
      }

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * index "a_relationship_name_longer_than_thirty_three_bytes_9e7c7fc8_$pk" is derived from relationship :a_relationship_name_longer_than_thirty_three_bytes_x1 in Nonexistent.Post, the primary key of :"Elixir.ARelationshipNameLongerThanThirtyThreeBytes.9e7c7fc8"\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> derive_from_model!(model) end
    end

    test "derives the same mapping as derive!/2" do
      entity_types = Reflection.list_entities()
      role_modules = Reflection.list_roles()
      model = Model.from_modules(entity_types, role_modules)

      assert derive_from_model!(model) == derive!(entity_types, role_modules)
    end

    test "derives a unique index from a term's attribute options" do
      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [{:name, :string, [unique: true]}],
            relationships: [],
            roles: [],
            uniques: []
          }
        },
        roles: %{},
        user_entity: nil
      }

      mapping = derive_from_model!(model)

      assert mapping[Nonexistent.Ghost].indexes == %{
               "nonexistent_ghost_name_$uidx" => %{
                 columns: ["name"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "derives a unique index per key, over its fields' columns in declared order" do
      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [{:name, :string, []}, {:rank, :integer, [optional: true]}],
            relationships: [{:owner, Nonexistent.Ghost, [optional: true]}],
            roles: [],
            uniques: [[:owner, :name], [:rank, :owner]]
          }
        },
        roles: %{},
        user_entity: nil
      }

      mapping = derive_from_model!(model)

      assert mapping[Nonexistent.Ghost].indexes == %{
               "nonexistent_ghost_owner_id_name_$uidx" => %{
                 columns: ["owner_id", "name"],
                 nulls_distinct: true,
                 unique: true
               },
               "nonexistent_ghost_rank_owner_id_$uidx" => %{
                 columns: ["rank", "owner_id"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "cuts a key's index name that does not fit, keeping its digest and kind" do
      long_field = :aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      long = Atom.to_string(long_field)

      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [{long_field, :string, []}, {:name, :string, []}],
            relationships: [],
            roles: [],
            uniques: [[long_field, :name]]
          }
        },
        roles: %{},
        user_entity: nil
      }

      [{name, index}] = Map.to_list(derive_from_model!(model)[Nonexistent.Ghost].indexes)

      assert index.columns == [long, "name"]
      assert byte_size(name) <= 63
      assert name == fit_identifier(["nonexistent", "ghost"], [long, "name"], "$uidx")
      assert String.ends_with?(name, "_$uidx")
    end

    test "reports a key's index another entity type's unique attribute derives too" do
      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [{:name, :string, []}, {:tag, :string, []}],
            relationships: [],
            roles: [],
            uniques: [[:name, :tag]]
          },
          Nonexistent.GhostName => %{
            attributes: [{:tag, :string, [unique: true]}],
            relationships: [],
            roles: [],
            uniques: []
          }
        },
        roles: %{},
        user_entity: nil
      }

      expected_msg =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * index "nonexistent_ghost_name_tag_$uidx" is derived from attribute :tag in Nonexistent.GhostName, unique [:name, :tag] in Nonexistent.Ghost\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> derive_from_model!(model) end
    end

    test "derives a unique index from a term's to-one relationship options" do
      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [],
            relationships: [{:owner, Nonexistent.Ghost, [optional: true, unique: true]}],
            roles: [],
            uniques: []
          }
        },
        roles: %{},
        user_entity: nil
      }

      mapping = derive_from_model!(model)

      assert mapping[Nonexistent.Ghost].indexes == %{
               "nonexistent_ghost_owner_id_$uidx" => %{
                 columns: ["owner_id"],
                 nulls_distinct: true,
                 unique: true
               }
             }
    end

    test "derives without consulting any module" do
      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [{:name, :string, []}],
            relationships: [],
            roles: [],
            uniques: []
          }
        },
        roles: %{},
        user_entity: nil
      }

      mapping = derive_from_model!(model)

      assert mapping[Nonexistent.Ghost].table == "nonexistent_ghost"
    end

    # The designation is a term fact rather than a module reflection, so a history whose
    # user entity type was renamed later still derives the store at every point - before
    # this, the rename made the store vanish from every model preceding it.
    test "derives the grant store for the entity type the term designates" do
      model = %{
        entities: %{Module1 => %{attributes: [], relationships: [], roles: [], uniques: []}},
        roles: %{},
        user_entity: Module1
      }

      mapping = derive_from_model!(model)

      assert mapping[RoleGrant].table == "hologram_role_grant"
    end

    test "derives no grant store for a term designating no user entity type" do
      model = %{
        entities: %{Module14 => %{attributes: [], relationships: [], roles: [], uniques: []}},
        roles: %{},
        user_entity: nil
      }

      mapping = derive_from_model!(model)

      assert Map.has_key?(mapping, RoleGrant) == false
    end

    test "derives the grant store's enum values from the term" do
      model = %{
        entities: %{
          Module14 => %{attributes: [], relationships: [], roles: [{:editor, []}], uniques: []}
        },
        roles: %{Nonexistent.Roles.Admin => %{extends: []}},
        user_entity: Module14
      }

      mapping = derive_from_model!(model)

      entity_type_column =
        Enum.find(mapping[RoleGrant].columns, &(&1.source == {:attribute, :entity_type}))

      role_column = Enum.find(mapping[RoleGrant].columns, &(&1.source == {:attribute, :role}))

      assert entity_type_column.enum_values == ["Hologram.Test.Fixtures.Entity.Module14"]
      assert role_column.enum_values == ["Nonexistent.Roles.Admin", "editor"]
    end

    # The store's own check, and the only one either set gets: both are derived from the model
    # rather than declared, so Hologram.Entity.Validator - which refuses a declared enum value or
    # role name past the limit - never sees them. A label PostgreSQL truncates no longer decodes
    # to the value it was stored for, so the grant it names is read back as somebody else's.
    test "refuses an entity type whose name does not fit an enum label" do
      entity_type = Nonexistent.Entities.NameOneByteLongerThanAnEnumLabelWillHoldXyz

      model = %{
        entities: %{entity_type => %{attributes: [], relationships: [], roles: [], uniques: []}},
        roles: %{},
        user_entity: entity_type
      }

      expected_msg =
        "entity type Nonexistent.Entities.NameOneByteLongerThanAnEnumLabelWillHoldXyz is too " <>
          "long to store in the role grant store (64 bytes, limit 63) - shorten the module name"

      assert_error Hologram.CompileError, expected_msg, fn -> derive_from_model!(model) end
    end

    test "refuses a global role module whose name does not fit an enum label" do
      role_module = Nonexistent.Roles.NameOneByteLongerThanAnEnumLabelWillHoldAbcdef

      model = %{
        entities: %{Module14 => %{attributes: [], relationships: [], roles: [], uniques: []}},
        roles: %{role_module => %{extends: []}},
        user_entity: Module14
      }

      expected_msg =
        "global role Nonexistent.Roles.NameOneByteLongerThanAnEnumLabelWillHoldAbcdef is too " <>
          "long to store in the role grant store (64 bytes, limit 63) - shorten the module name"

      assert_error Hologram.CompileError, expected_msg, fn -> derive_from_model!(model) end
    end

    test "accepts a name that fills an enum label to its last byte" do
      entity_type = Nonexistent.Entities.NameFillingTheEnumLabelToItsVeryLastByteAb

      model = %{
        entities: %{entity_type => %{attributes: [], relationships: [], roles: [], uniques: []}},
        roles: %{},
        user_entity: entity_type
      }

      mapping = derive_from_model!(model)

      entity_type_column =
        Enum.find(mapping[RoleGrant].columns, &(&1.source == {:attribute, :entity_type}))

      assert entity_type_column.enum_values == [
               "Nonexistent.Entities.NameFillingTheEnumLabelToItsVeryLastByteAb"
             ]
    end
  end

  describe "derived?/1" do
    test "is true for a sort-key companion" do
      assert derived?(%{source: {:sort_key, :c}}) == true
    end

    test "is true for a search-key companion" do
      assert derived?(%{source: {:search_key, :c}}) == true
    end

    test "is false for an attribute's own column" do
      assert derived?(%{source: {:attribute, :c}}) == false
    end
  end

  describe "fit_identifier/3" do
    test "joins the parts with single underscores when the name fits" do
      assert fit_identifier(["task"], ["status"], "$enum") == "task_status_$enum"
    end

    test "leaves out the kind when there is none" do
      assert fit_identifier(["blog", "post"], [], nil) == "blog_post"
    end

    test "returns a 63-byte name unchanged" do
      column = String.duplicate("a", 50)

      assert fit_identifier(["invoice"], [column], "$idx") == "invoice_#{column}_$idx"
    end

    test "drops the leading table segments first, keeping the column, a digest and the kind" do
      assert fit_identifier(
               ["billing", "subscriptions", "recurring_invoice_line_item"],
               ["subscription_id"],
               "$fk"
             ) == "recurring_invoice_line_item_subscription_id_aa227011_$fk"
    end

    test "drops a leading table segment only as far as the name needs" do
      assert fit_identifier(
               ["billing_department_long", "plans", "invoice_line_item"],
               ["subscription_id"],
               "$fk"
             ) == "plans_invoice_line_item_subscription_id_446e67d8_$fk"
    end

    test "drops the table's context before any column" do
      assert fit_identifier(
               ["billing_and_accounts", "subscriptions"],
               ["first_column", "second_column"],
               "$uidx"
             ) == "subscriptions_first_column_second_column_603c0d2b_$uidx"
    end

    test "drops trailing columns whole once the table is down to its own name" do
      columns = ["first_quite_long_column", "second_quite_long_column", "third_column"]

      assert fit_identifier(["post"], columns, "$uidx") ==
               "post_first_quite_long_column_08083a7a_$uidx"
    end

    test "drops the entity's own name before the lone column, then cuts the column" do
      column = String.duplicate("a", 51)

      assert fit_identifier(["invoice"], [column], "$idx") ==
               String.duplicate("a", 49) <> "_0c8244ba_$idx"
    end

    test "cuts at a character boundary" do
      column = String.duplicate("ż", 40)

      assert fit_identifier([], [column], "id") ==
               String.duplicate("ż", 25) <> "_a25d842e_id"
    end

    test "trims the underscores a cut leaves at the end" do
      column = String.duplicate("a", 50) <> "_" <> String.duplicate("b", 20)

      assert fit_identifier([], [column], "id") ==
               String.duplicate("a", 50) <> "_fd0eaed7_id"
    end

    test "keeps the digest and the kind alone when nothing is left after the cut" do
      assert fit_identifier([], [String.duplicate("_", 70)], "id") == "5b6791bf_id"
    end

    test "gives names that differ only in a dropped part different digests" do
      segments = ["subscriptions", "recurring_invoice_line_item"]

      billing = fit_identifier(["billing" | segments], ["subscription_id"], "$fk")
      accounting = fit_identifier(["accounting" | segments], ["subscription_id"], "$fk")

      assert billing != accounting

      assert String.replace(billing, ~r/_[0-9a-f]{8}_/, "_") ==
               String.replace(accounting, ~r/_[0-9a-f]{8}_/, "_")
    end
  end

  describe "join_tables/1" do
    test "returns empty list for entity type with no to-many relationships" do
      assert join_tables(Module1) == []
    end

    test "derives join tables for to-many relationships and excludes to-one relationships" do
      assert join_tables(Module3) == [
               %{
                 name: "test_fixtures_entity_module3_a_$join",
                 relationship: :a,
                 source_table: "test_fixtures_entity_module3",
                 target_table: "test_fixtures_entity_module2",
                 pk_constraint: "test_fixtures_entity_module3_a_$join_$pk",
                 source_fk_constraint: "test_fixtures_entity_module3_a_$join_source_id_$fk",
                 target_fk_constraint: "test_fixtures_entity_module3_a_$join_target_id_$fk"
               }
             ]
    end

    test "derives join tables for self-referential to-many relationships" do
      defmodule InlineEntityFixture2 do
        use Hologram.Entity

        relationship :parts, [__MODULE__]
      end

      assert [join_table] = join_tables(InlineEntityFixture2)
      assert join_table.source_table == join_table.target_table
    end

    test "keeps the relationship, $join and the kind in a join table's names over the PostgreSQL identifier limit" do
      defmodule InlineEntityFixture23 do
        use Hologram.Entity

        relationship :recurring_invoice_adjustments, [Module1]
      end

      assert [join_table] = join_tables(InlineEntityFixture23)

      assert join_table.name == "recurring_invoice_adjustments_f97af6f0_$join"

      assert join_table.pk_constraint == "recurring_invoice_adjustments_$join_23c0665c_$pk"

      assert join_table.source_fk_constraint ==
               "recurring_invoice_adjustments_$join_source_id_74bcced4_$fk"

      assert join_table.target_fk_constraint ==
               "recurring_invoice_adjustments_$join_target_id_59be50d0_$fk"
    end
  end

  describe "quote_identifier/1" do
    test "wraps the identifier in double quotes" do
      assert quote_identifier("blog_post") == ~s("blog_post")
    end

    test "escapes embedded double quotes" do
      assert quote_identifier(~s(blog"post)) == ~s("blog""post")
    end
  end

  describe "referencing_relationship/2" do
    test "names the entity type and relationship of a to-one reference column" do
      mapping = derive!([Module1, Module2, Module3], [])
      constraint = "test_fixtures_entity_module3_c_id_$fk"

      assert referencing_relationship(mapping, constraint) == {Module3, :c}
    end

    test "names the entity type and relationship of a join table's target" do
      mapping = derive!([Module1, Module2, Module3], [])
      constraint = "test_fixtures_entity_module3_a_$join_target_id_$fk"

      assert referencing_relationship(mapping, constraint) == {Module3, :a}
    end

    test "names the grant store's user reference" do
      mapping = derive!([Module1, Module14], [])

      constraint =
        mapping[RoleGrant].columns
        |> Enum.find(&(&1.name == "user_id"))
        |> Map.fetch!(:fk_constraint)

      assert referencing_relationship(mapping, constraint) == {RoleGrant, :user}
    end

    test "returns nil for a constraint no relationship derives" do
      mapping = derive!([Module1, Module2, Module3], [])

      assert referencing_relationship(mapping, "nope_$fk") == nil
    end
  end

  describe "system_schema/0" do
    test "returns the schema of the bookkeeping tables" do
      assert system_schema() == "hologram_system"
    end
  end

  # The primary OTP app root in this test suite is Hologram (Reflection.otp_app() == :hologram).
  describe "table_name/1" do
    test "pins the role grant table to its full path" do
      assert table_name(Hologram.Auth.RoleGrant) == "hologram_role_grant"
    end

    test "snake cases the module path with the primary app root stripped" do
      assert table_name(Hologram.Blog.Post) == "blog_post"
    end

    test "snake cases multi-word segments" do
      assert table_name(Hologram.BlogPost) == "blog_post"
    end

    test "keeps the full path for modules outside the primary app root" do
      assert table_name(LibKanban.Task) == "lib_kanban_task"
    end

    test "keeps a single-segment module name equal to the primary app root" do
      assert table_name(Hologram) == "hologram"
    end

    test "shortens names over the PostgreSQL identifier limit to the entity's own name plus a deterministic hash" do
      entity_type =
        Hologram.SomeDeeplyNested.EntityTypeModule.WithAnExtraordinarilyLong.MultiSegmentName

      assert table_name(entity_type) == "with_an_extraordinarily_long_multi_segment_name_e6841b3f"
    end
  end

  describe "validate_required_to_one_cycles!/1" do
    test "returns :ok for an empty list" do
      assert validate_required_to_one_cycles!([]) == :ok
    end

    test "returns :ok when no required to-one cycles exist" do
      assert validate_required_to_one_cycles!([Module1, Module2, Module3]) == :ok
    end

    test "returns :ok when a cycle is broken by an optional to-one relationship" do
      defmodule InlineEntityFixture3 do
        use Hologram.Entity

        relationship :b, Hologram.DB.MapperTest.InlineEntityFixture4
      end

      defmodule InlineEntityFixture4 do
        use Hologram.Entity

        relationship :a, Hologram.DB.MapperTest.InlineEntityFixture3, optional: true
      end

      assert validate_required_to_one_cycles!([InlineEntityFixture3, InlineEntityFixture4]) ==
               :ok
    end

    test "returns :ok when a cycle is broken by a to-many relationship" do
      defmodule InlineEntityFixture5 do
        use Hologram.Entity

        relationship :b, Hologram.DB.MapperTest.InlineEntityFixture6
      end

      defmodule InlineEntityFixture6 do
        use Hologram.Entity

        relationship :a, [Hologram.DB.MapperTest.InlineEntityFixture5]
      end

      assert validate_required_to_one_cycles!([InlineEntityFixture5, InlineEntityFixture6]) ==
               :ok
    end

    test "rejects a self-referential required to-one relationship" do
      defmodule InlineEntityFixture7 do
        use Hologram.Entity

        relationship :parent, __MODULE__
      end

      expected_msg =
        normalize_newlines("""
        cyclic required to-one relationships - no row in such a cycle can ever be created, mark at least one relationship in each cycle as optional: true:
          * Hologram.DB.MapperTest.InlineEntityFixture7 (relationship :parent) -> Hologram.DB.MapperTest.InlineEntityFixture7\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_required_to_one_cycles!([InlineEntityFixture7])
      end
    end

    test "rejects a cycle across multiple entity types" do
      defmodule InlineEntityFixture8 do
        use Hologram.Entity

        relationship :next, Hologram.DB.MapperTest.InlineEntityFixture9
      end

      defmodule InlineEntityFixture9 do
        use Hologram.Entity

        relationship :back, Hologram.DB.MapperTest.InlineEntityFixture8
      end

      expected_msg =
        normalize_newlines("""
        cyclic required to-one relationships - no row in such a cycle can ever be created, mark at least one relationship in each cycle as optional: true:
          * Hologram.DB.MapperTest.InlineEntityFixture8 (relationship :next) -> Hologram.DB.MapperTest.InlineEntityFixture9 (relationship :back) -> Hologram.DB.MapperTest.InlineEntityFixture8\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_required_to_one_cycles!([InlineEntityFixture8, InlineEntityFixture9])
      end
    end

    test "lists every cycle when multiple cycles exist" do
      defmodule InlineEntityFixture10 do
        use Hologram.Entity

        relationship :parent, __MODULE__
      end

      defmodule InlineEntityFixture11 do
        use Hologram.Entity

        relationship :next, Hologram.DB.MapperTest.InlineEntityFixture12
      end

      defmodule InlineEntityFixture12 do
        use Hologram.Entity

        relationship :back, Hologram.DB.MapperTest.InlineEntityFixture11
      end

      expected_msg =
        normalize_newlines("""
        cyclic required to-one relationships - no row in such a cycle can ever be created, mark at least one relationship in each cycle as optional: true:
          * Hologram.DB.MapperTest.InlineEntityFixture10 (relationship :parent) -> Hologram.DB.MapperTest.InlineEntityFixture10
          * Hologram.DB.MapperTest.InlineEntityFixture11 (relationship :next) -> Hologram.DB.MapperTest.InlineEntityFixture12 (relationship :back) -> Hologram.DB.MapperTest.InlineEntityFixture11\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_required_to_one_cycles!([
          InlineEntityFixture10,
          InlineEntityFixture11,
          InlineEntityFixture12
        ])
      end
    end
  end

  describe "validate_table_names!/1" do
    test "returns :ok for an empty list" do
      assert validate_table_names!([]) == :ok
    end

    test "returns :ok when every derived table name is unique" do
      assert validate_table_names!([Hologram.Blog.Post, LibKanban.Task]) == :ok
    end

    test "rejects modules deriving the same table name" do
      expected_msg =
        normalize_newlines("""
        colliding table names - rename modules so that every entity type derives a unique table name:
          * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_table_names!([Hologram.Blog.Post, Hologram.BlogPost])
      end
    end

    test "lists all modules when more than two derive the same table name" do
      expected_msg =
        normalize_newlines("""
        colliding table names - rename modules so that every entity type derives a unique table name:
          * table name "blog_post" is derived from Blog.Post, Hologram.Blog.Post, Hologram.BlogPost\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_table_names!([Blog.Post, Hologram.Blog.Post, Hologram.BlogPost])
      end
    end

    test "lists every collision group when multiple table names collide" do
      expected_msg =
        normalize_newlines("""
        colliding table names - rename modules so that every entity type derives a unique table name:
          * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost
          * table name "task_list" is derived from Hologram.Task.List, Hologram.TaskList\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_table_names!([
          Hologram.Blog.Post,
          Hologram.BlogPost,
          Hologram.Task.List,
          Hologram.TaskList
        ])
      end
    end
  end
end
