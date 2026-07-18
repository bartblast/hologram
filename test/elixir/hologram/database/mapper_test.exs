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
                 null: false,
                 references: nil,
                 source: :system
               },
               %{
                 name: "created_at",
                 type: :datetime,
                 sql_type: "timestamptz",
                 null: false,
                 references: nil,
                 source: :system
               },
               %{
                 name: "updated_at",
                 type: :datetime,
                 sql_type: "timestamptz",
                 null: false,
                 references: nil,
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
                 null: false,
                 references: nil,
                 source: {:attribute, :a}
               },
               %{
                 name: "b",
                 type: :integer,
                 sql_type: "int8",
                 null: true,
                 references: nil,
                 source: {:attribute, :b}
               },
               %{
                 name: "c",
                 type: :string,
                 sql_type: ~s(text COLLATE "C"),
                 null: false,
                 references: nil,
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
      assert column(Module2, "c").sql_type == ~s(text COLLATE "C")
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
                 null: true,
                 references: "test_fixtures_entity_module2",
                 source: {:relationship, :b}
               },
               %{
                 name: "c_id",
                 type: :uuid,
                 sql_type: "uuid",
                 null: false,
                 references: "test_fixtures_entity_module1",
                 source: {:relationship, :c}
               }
             ]
    end

    test "rejects declarations deriving the same column name" do
      defmodule InlineEntityFixture1 do
        use Hologram.Entity

        attribute :project_id, :string
        relationship :project, Module1
      end

      expected_msg = """
      colliding column names in Hologram.Database.MapperTest.InlineEntityFixture1 - rename the declarations so that every derived column name is unique:
        * column "project_id" is derived from attribute :project_id, relationship :project\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        columns(InlineEntityFixture1)
      end
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

  describe "validate_table_names!/1" do
    test "returns :ok for an empty list" do
      assert validate_table_names!([]) == :ok
    end

    test "returns :ok when every derived table name is unique" do
      assert validate_table_names!([Hologram.Blog.Post, LibKanban.Task]) == :ok
    end

    test "rejects modules deriving the same table name" do
      expected_msg = """
      colliding table names - rename modules so that every entity type derives a unique table name:
        * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_table_names!([Hologram.Blog.Post, Hologram.BlogPost])
      end
    end

    test "lists all modules when more than two derive the same table name" do
      expected_msg = """
      colliding table names - rename modules so that every entity type derives a unique table name:
        * table name "blog_post" is derived from Blog.Post, Hologram.Blog.Post, Hologram.BlogPost\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_table_names!([Blog.Post, Hologram.Blog.Post, Hologram.BlogPost])
      end
    end

    test "lists every collision group when multiple table names collide" do
      expected_msg = """
      colliding table names - rename modules so that every entity type derives a unique table name:
        * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost
        * table name "task_list" is derived from Hologram.Task.List, Hologram.TaskList\
      """

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
