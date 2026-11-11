defmodule Hologram.DerivedTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Derived

  defp env do
    %{
      __ENV__
      | file: Path.join(File.cwd!(), "lib/my_app/task_list.ex"),
        line: 7,
        module: MyApp.TaskList
    }
  end

  defp captured_from(code) do
    code
    |> Code.string_to_quoted!()
    |> captured()
  end

  defp quoted_function(code) do
    definition = Code.string_to_quoted!(code, line: 7)

    :tags
    |> function(definition, env())
    |> Macro.to_string()
  end

  describe "captured/1" do
    test "returns how a local capture spells its function, with the arity" do
      assert captured_from("&tags_query/0") == {"tags_query", 0}
    end

    test "returns how a remote capture spells its function, with the arity" do
      assert captured_from("&MyApp.Queries.tags/2") ==
               {"MyApp.Queries.tags", 2}
    end

    test "returns nil for the capture shorthand" do
      assert captured_from("&tags_query(&1)") == nil
    end

    test "returns nil for a function" do
      assert captured_from("fn -> tags_query() end") == nil
    end
  end

  describe "function/3" do
    test "stands a local zero-arity capture for the function calling it" do
      assert quoted_function("&tags_query/0") == "fn -> tags_query() end"
    end

    test "stands a remote zero-arity capture for the function calling it" do
      assert quoted_function("&MyApp.Queries.tags/0") == "fn -> MyApp.Queries.tags() end"
    end

    test "returns a function as given" do
      assert quoted_function("fn project_id -> tags_query(project_id) end") ==
               "fn project_id -> tags_query(project_id) end"
    end

    test "returns the capture shorthand as given" do
      assert quoted_function("&tags_query(&1)") == "&tags_query(&1)"
    end

    test "raises on a local capture with arguments" do
      expected_msg =
        "lib/my_app/task_list.ex:7: derived field :tags in MyApp.TaskList is a capture of tags_query/1, which hides the fields it reads - write fn ... -> tags_query(...) end, naming them in the head"

      assert_error Hologram.CompileError, expected_msg, fn ->
        quoted_function("&tags_query/1")
      end
    end

    test "raises on a remote capture with arguments" do
      expected_msg =
        "lib/my_app/task_list.ex:7: derived field :tags in MyApp.TaskList is a capture of MyApp.Queries.tags/2, which hides the fields it reads - write fn ... -> MyApp.Queries.tags(...) end, naming them in the head"

      assert_error Hologram.CompileError, expected_msg, fn ->
        quoted_function("&MyApp.Queries.tags/2")
      end
    end
  end
end
