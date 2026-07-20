defmodule Hologram.Database.MapperTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.Mapper

  alias Hologram.Test.Fixtures.Entity.Module1
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
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 fk_index: nil,
                 source: :system
               },
               %{
                 name: "created_at",
                 type: :datetime,
                 sql_type: "timestamptz",
                 collation: nil,
                 enum_values: nil,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 fk_index: nil,
                 source: :system
               },
               %{
                 name: "updated_at",
                 type: :datetime,
                 sql_type: "timestamptz",
                 collation: nil,
                 enum_values: nil,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 fk_index: nil,
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
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 fk_index: nil,
                 source: {:attribute, :a}
               },
               %{
                 name: "b",
                 type: :integer,
                 sql_type: "int8",
                 collation: nil,
                 enum_values: nil,
                 null: true,
                 references: nil,
                 fk_constraint: nil,
                 fk_index: nil,
                 source: {:attribute, :b}
               },
               %{
                 name: "c",
                 type: :string,
                 sql_type: "text",
                 collation: "C",
                 enum_values: nil,
                 null: false,
                 references: nil,
                 fk_constraint: nil,
                 fk_index: nil,
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

    test "derives nil collation for types that carry none" do
      assert column(Module2, "a").collation == nil
    end

    test "carries enum values as strings in declaration order" do
      assert column(Module4, "c").enum_values == ["x", "y"]
    end

    test "derives nil enum values for non-enum types" do
      assert column(Module4, "a").enum_values == nil
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
                 null: true,
                 references: "test_fixtures_entity_module2",
                 fk_constraint: "test_fixtures_entity_module3_b_id_$fk",
                 fk_index: "test_fixtures_entity_module3_b_id_$idx",
                 source: {:relationship, :b}
               },
               %{
                 name: "c_id",
                 type: :uuid,
                 sql_type: "uuid",
                 collation: nil,
                 enum_values: nil,
                 null: false,
                 references: "test_fixtures_entity_module1",
                 fk_constraint: "test_fixtures_entity_module3_c_id_$fk",
                 fk_index: "test_fixtures_entity_module3_c_id_$idx",
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
               "database_mapper_test_inline_entity_fixture17_quite_lon_9f01ea3f"
    end

    test "shortens foreign key index names over the PostgreSQL identifier limit" do
      defmodule InlineEntityFixture18 do
        use Hologram.Entity

        relationship :quite_long_relationship_name, Module1
      end

      assert column(InlineEntityFixture18, "quite_long_relationship_name_id").fk_index ==
               "database_mapper_test_inline_entity_fixture18_quite_lon_70323e73"
    end

    test "rejects declarations deriving the same column name" do
      defmodule InlineEntityFixture1 do
        use Hologram.Entity

        attribute :project_id, :string
        relationship :project, Module1
      end

      expected_msg =
        normalize_newlines("""
        colliding column names in Hologram.Database.MapperTest.InlineEntityFixture1 - rename the declarations so that every derived column name is unique:
          * column "project_id" is derived from attribute :project_id, relationship :project\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        columns(InlineEntityFixture1)
      end
    end
  end

  describe "derive!/1" do
    test "returns the mapping keyed by entity type" do
      assert derive!([Module1, Module3]) == %{
               Module1 => %{
                 table: table_name(Module1),
                 pk_constraint: "test_fixtures_entity_module1_$pk",
                 columns: columns(Module1),
                 join_tables: join_tables(Module1)
               },
               Module3 => %{
                 table: table_name(Module3),
                 pk_constraint: "test_fixtures_entity_module3_$pk",
                 columns: columns(Module3),
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
          * Hologram.Database.MapperTest.InlineEntityFixture13 (relationship :parent) -> Hologram.Database.MapperTest.InlineEntityFixture13\
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
          * join table "database_mapper_test_inline_entity_fixture14_b_c_$join" is derived from relationship :b_c in Hologram.Database.MapperTest.InlineEntityFixture14, relationship :c in Hologram.Database.MapperTest.InlineEntityFixture14B\
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
          * enum type "database_mapper_test_inline_entity_fixture15_b_p_$enum" is derived from attribute :b_p in Hologram.Database.MapperTest.InlineEntityFixture15, attribute :p in Hologram.Database.MapperTest.InlineEntityFixture15B\
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
          * enum type "database_mapper_test_inline_entity_fixture16_b_p_$enum" is derived from attribute :b_p in Hologram.Database.MapperTest.InlineEntityFixture16, attribute :p in Hologram.Database.MapperTest.InlineEntityFixture16B
          * join table "database_mapper_test_inline_entity_fixture16_b_r_$join" is derived from relationship :b_r in Hologram.Database.MapperTest.InlineEntityFixture16, relationship :r in Hologram.Database.MapperTest.InlineEntityFixture16B\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derive!([InlineEntityFixture16, InlineEntityFixture16B])
      end
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

  # The primary OTP app root in this test suite is Hologram (Reflection.otp_app() == :hologram).
  describe "table_name/1" do
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

        relationship :b, Hologram.Database.MapperTest.InlineEntityFixture4
      end

      defmodule InlineEntityFixture4 do
        use Hologram.Entity

        relationship :a, Hologram.Database.MapperTest.InlineEntityFixture3, optional: true
      end

      assert validate_required_to_one_cycles!([InlineEntityFixture3, InlineEntityFixture4]) ==
               :ok
    end

    test "returns :ok when a cycle is broken by a to-many relationship" do
      defmodule InlineEntityFixture5 do
        use Hologram.Entity

        relationship :b, Hologram.Database.MapperTest.InlineEntityFixture6
      end

      defmodule InlineEntityFixture6 do
        use Hologram.Entity

        relationship :a, [Hologram.Database.MapperTest.InlineEntityFixture5]
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
          * Hologram.Database.MapperTest.InlineEntityFixture7 (relationship :parent) -> Hologram.Database.MapperTest.InlineEntityFixture7\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_required_to_one_cycles!([InlineEntityFixture7])
      end
    end

    test "rejects a cycle across multiple entity types" do
      defmodule InlineEntityFixture8 do
        use Hologram.Entity

        relationship :next, Hologram.Database.MapperTest.InlineEntityFixture9
      end

      defmodule InlineEntityFixture9 do
        use Hologram.Entity

        relationship :back, Hologram.Database.MapperTest.InlineEntityFixture8
      end

      expected_msg =
        normalize_newlines("""
        cyclic required to-one relationships - no row in such a cycle can ever be created, mark at least one relationship in each cycle as optional: true:
          * Hologram.Database.MapperTest.InlineEntityFixture8 (relationship :next) -> Hologram.Database.MapperTest.InlineEntityFixture9 (relationship :back) -> Hologram.Database.MapperTest.InlineEntityFixture8\
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

        relationship :next, Hologram.Database.MapperTest.InlineEntityFixture12
      end

      defmodule InlineEntityFixture12 do
        use Hologram.Entity

        relationship :back, Hologram.Database.MapperTest.InlineEntityFixture11
      end

      expected_msg =
        normalize_newlines("""
        cyclic required to-one relationships - no row in such a cycle can ever be created, mark at least one relationship in each cycle as optional: true:
          * Hologram.Database.MapperTest.InlineEntityFixture10 (relationship :parent) -> Hologram.Database.MapperTest.InlineEntityFixture10
          * Hologram.Database.MapperTest.InlineEntityFixture11 (relationship :next) -> Hologram.Database.MapperTest.InlineEntityFixture12 (relationship :back) -> Hologram.Database.MapperTest.InlineEntityFixture11\
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
