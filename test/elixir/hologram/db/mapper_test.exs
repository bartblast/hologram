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
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

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
                 index: nil,
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
                 index: nil,
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
                 index: nil,
                 source: :system
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
                 index: nil,
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
                 index: nil,
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
                 index: nil,
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
               index: nil,
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
        |> List.last()

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
               index: "test_fixtures_entity_module2_c_$sort_$idx",
               source: {:sort_key, :c}
             }
    end

    test "derives the companions in attribute-name order, server-only attributes included" do
      sources =
        Module15
        |> columns()
        |> Enum.take(-3)
        |> Enum.map(& &1.source)

      assert sources == [{:sort_key, :label}, {:sort_key, :secret_note}, {:sort_key, :token}]
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
                 index: "test_fixtures_entity_module3_b_id_$idx",
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
                 index: "test_fixtures_entity_module3_c_id_$idx",
                 source: {:relationship, :c}
               }
             ]
    end

    test "shortens foreign key constraint names over the PostgreSQL identifier limit" do
      defmodule InlineEntityFixture17 do
        use Hologram.Entity

        relationship :quite_long_relationship_name, Module1
      end

      assert column(InlineEntityFixture17, "quite_long_relationship_name_id").fk_constraint ==
               "db_mapper_test_inline_entity_fixture17_quite_long_rela_e26c80e5"
    end

    test "shortens foreign key index names over the PostgreSQL identifier limit" do
      defmodule InlineEntityFixture18 do
        use Hologram.Entity

        relationship :quite_long_relationship_name, Module1
      end

      assert column(InlineEntityFixture18, "quite_long_relationship_name_id").index ==
               "db_mapper_test_inline_entity_fixture18_quite_long_rela_90ec8e14"
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
  end

  describe "derive!/1" do
    test "derives the role grant unique index comparing nulls as values" do
      mapping =
        derive!([
          Hologram.Auth.RoleGrant,
          Hologram.Test.Fixtures.Entity.Module14,
          Module1
        ])

      assert mapping[Hologram.Auth.RoleGrant].indexes == %{
               "hologram_role_grant_$uidx" => %{
                 columns: ["user_id", "resource_type", "resource_id", "role"],
                 nulls_distinct: false,
                 unique: true
               }
             }
    end

    test "derives a unique index per unique attribute" do
      mapping = derive!([Module19])

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
      mapping = derive!([Module2])

      assert mapping[Module2].indexes == %{}
    end

    test "carries a sort-key companion for every string attribute" do
      mapping = derive!([Module2])

      assert List.last(mapping[Module2].columns).source == {:sort_key, :c}
    end

    test "derives the role grant store alongside the app's user entity type" do
      mapping = derive!([Module1, Module14])

      assert mapping[RoleGrant].table == "hologram_role_grant"
    end

    test "derives no role grant store for a model without the user entity type" do
      mapping = derive!([Module1])

      assert Map.has_key?(mapping, RoleGrant) == false
    end

    test "returns the mapping keyed by entity type" do
      mapping =
        [Module1, Module3]
        |> derive!()
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
        derive!([Hologram.Blog.Post, Hologram.BlogPost])
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
        derive!([InlineEntityFixture13])
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
        derive!([InlineEntityFixture14, InlineEntityFixture14B])
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
        derive!([InlineEntityFixture15, InlineEntityFixture15B])
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
        derive!([InlineEntityFixture16, InlineEntityFixture16B])
      end
    end
  end

  describe "derive_from_model!/1" do
    test "derives the same mapping as derive!/1" do
      entity_types = Reflection.list_entities()
      model = Model.from_modules(entity_types, Reflection.list_roles())

      assert derive_from_model!(model) == derive!(entity_types)
    end

    test "derives a unique index from a term's attribute options" do
      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [{:name, :string, [unique: true]}],
            relationships: [],
            roles: []
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

    test "derives without consulting any module" do
      model = %{
        entities: %{
          Nonexistent.Ghost => %{
            attributes: [{:name, :string, []}],
            relationships: [],
            roles: []
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
        entities: %{Module1 => %{attributes: [], relationships: [], roles: []}},
        roles: %{},
        user_entity: Module1
      }

      mapping = derive_from_model!(model)

      assert mapping[RoleGrant].table == "hologram_role_grant"
    end

    test "derives no grant store for a term designating no user entity type" do
      model = %{
        entities: %{Module14 => %{attributes: [], relationships: [], roles: []}},
        roles: %{},
        user_entity: nil
      }

      mapping = derive_from_model!(model)

      assert Map.has_key?(mapping, RoleGrant) == false
    end

    test "derives the grant store's enum values from the term" do
      model = %{
        entities: %{
          Module14 => %{attributes: [], relationships: [], roles: [{:editor, []}]}
        },
        roles: %{Nonexistent.Roles.Admin => %{extends: []}},
        user_entity: Module14
      }

      mapping = derive_from_model!(model)

      resource_type_column =
        Enum.find(mapping[RoleGrant].columns, &(&1.source == {:attribute, :resource_type}))

      role_column = Enum.find(mapping[RoleGrant].columns, &(&1.source == {:attribute, :role}))

      assert resource_type_column.enum_values == ["test_fixtures_entity_module14"]
      assert role_column.enum_values == ["Nonexistent.Roles.Admin", "editor"]
    end
  end

  describe "fit_identifier/1" do
    test "returns identifiers within the PostgreSQL limit unchanged" do
      assert fit_identifier("task_status_$enum") == "task_status_$enum"
    end

    test "returns a 63-byte identifier unchanged" do
      identifier = String.duplicate("a", 63)

      assert fit_identifier(identifier) == identifier
    end

    test "shortens identifiers over the limit to a prefix plus a deterministic hash" do
      identifier = String.duplicate("a", 60) <> "_$enum"

      assert fit_identifier(identifier) ==
               "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa_2f41a680"
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
                 reverse_index: "test_fixtures_entity_module3_a_$join_target_id_$idx",
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
      mapping = derive!([Module1, Module2, Module3])
      constraint = "test_fixtures_entity_module3_c_id_$fk"

      assert referencing_relationship(mapping, constraint) == {Module3, :c}
    end

    test "names the entity type and relationship of a join table's target" do
      mapping = derive!([Module1, Module2, Module3])
      constraint = "test_fixtures_entity_module3_a_$join_target_id_$fk"

      assert referencing_relationship(mapping, constraint) == {Module3, :a}
    end

    test "names the grant store's user reference" do
      mapping = derive!([Module1, Module14])

      constraint =
        mapping[RoleGrant].columns
        |> Enum.find(&(&1.name == "user_id"))
        |> Map.fetch!(:fk_constraint)

      assert referencing_relationship(mapping, constraint) == {RoleGrant, :user}
    end

    test "returns nil for a constraint no relationship derives" do
      mapping = derive!([Module1, Module2, Module3])

      assert referencing_relationship(mapping, "nope_$fk") == nil
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

    test "shortens names over the PostgreSQL identifier limit to a prefix plus a deterministic hash" do
      entity_type =
        Hologram.SomeDeeplyNested.EntityTypeModule.WithAnExtraordinarilyLong.MultiSegmentName

      assert table_name(entity_type) ==
               "some_deeply_nested_entity_type_module_with_an_extraord_0889e0d6"
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
