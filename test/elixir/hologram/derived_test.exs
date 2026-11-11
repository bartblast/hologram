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

  defp quoted_function(code) do
    definition = Code.string_to_quoted!(code, line: 7)

    :tags
    |> function(definition, env())
    |> Macro.to_string()
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
