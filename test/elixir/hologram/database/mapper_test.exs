defmodule Hologram.Database.MapperTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.Mapper

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
