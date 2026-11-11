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

  describe "cycles/1" do
    test "returns the fields reading each other in a cycle" do
      result =
        %{a: [:b], b: [:a], c: []}
        |> cycles()
        |> Enum.map(&Enum.sort/1)

      assert result == [[:a, :b]]
    end

    test "returns each of several cycles" do
      result =
        %{a: [:b], b: [:a], x: [:y], y: [:x]}
        |> cycles()
        |> Enum.map(&Enum.sort/1)
        |> Enum.sort()

      assert result == [[:a, :b], [:x, :y]]
    end

    test "returns a field reading itself" do
      assert cycles(%{a: [:a], b: [:a]}) == [[:a]]
    end

    test "leaves out a field reading a cycle it is not on" do
      result =
        %{a: [:b], b: [:a], c: [:a]}
        |> cycles()
        |> Enum.map(&Enum.sort/1)

      assert result == [[:a, :b]]
    end

    test "returns none for a field reading a field not given" do
      assert cycles(%{a: [:b]}) == []
    end

    test "returns a cycle whose field also reads a field not given" do
      result =
        %{a: [:b, :x], b: [:a]}
        |> cycles()
        |> Enum.map(&Enum.sort/1)

      assert result == [[:a, :b]]
    end

    test "returns none when no field reads in a cycle" do
      assert cycles(%{a: [:b], b: [], c: [:a, :b]}) == []
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

  describe "validate_head!/5" do
    test "accepts names of fields" do
      assert validate_head!(
               MyApp.TaskList,
               :total,
               [:count],
               [:count, :step],
               {"lib/my_app/task_list.ex", 7}
             ) ==
               :ok
    end

    test "accepts names of fields given as strings" do
      assert validate_head!(
               MyApp.TaskList,
               :total,
               [:owner_id],
               ["owner_id"],
               {"lib/my_app/task_list.ex", 7}
             ) ==
               :ok
    end

    test "raises on the field's own name" do
      expected_msg =
        "lib/my_app/task_list.ex:7: derived field :total in MyApp.TaskList reads itself - a derived field is computed from other fields"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_head!(
          MyApp.TaskList,
          :total,
          [:total],
          [:count, :total],
          {"lib/my_app/task_list.ex", 7}
        )
      end
    end

    test "raises on a name that is no field, listing the fields sorted" do
      expected_msg =
        "lib/my_app/task_list.ex:7: size is not a field of MyApp.TaskList - the arguments of derived field :total's function name the fields it reads: count, step"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_head!(
          MyApp.TaskList,
          :total,
          [:size],
          [:step, :total, :count],
          {"lib/my_app/task_list.ex", 7}
        )
      end
    end

    test "raises on a name of a module declaring no other field" do
      expected_msg =
        "lib/my_app/task_list.ex:7: size is not a field of MyApp.TaskList - the arguments of derived field :total's function name the fields it reads, and MyApp.TaskList declares none"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_head!(MyApp.TaskList, :total, [:size], [:total], {"lib/my_app/task_list.ex", 7})
      end
    end
  end

  describe "validate_function!/3" do
    # The code is parsed at line 12 of a declaration written at line 7, so a refusal located at the
    # declaration names line 7.
    defp validate_function(code) do
      definition = Code.string_to_quoted!(code, line: 12)

      validate_function!(:unread_count, definition, env())
    end

    test "accepts a function of field names" do
      assert validate_function("fn channel, last_read_at -> channel end") == :ok
    end

    test "accepts a function of no fields" do
      assert validate_function("fn -> 1 end") == :ok
    end

    test "rejects a definition that is no function" do
      expected_msg =
        "lib/my_app/task_list.ex:7: derived field :unread_count in MyApp.TaskList is defined by a function whose arguments name the fields it reads, got: [to: Queries.unread_count(channel)] - write it as fn fields -> ... end, calling a shared query builder from the body if one computes it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("[to: Queries.unread_count(channel)]")
      end
    end

    test "rejects a function of several clauses" do
      expected_msg =
        "lib/my_app/task_list.ex:7: the function of derived field :unread_count in MyApp.TaskList has 2 clauses - a derived field's function has one clause, since its head names the fields it reads"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("fn nil -> 0\n channel -> channel end")
      end
    end

    test "rejects a pattern in the head" do
      expected_msg =
        "lib/my_app/task_list.ex:7: the arguments of derived field :unread_count in MyApp.TaskList's function name fields, each a bare name, got: %{id: id} - a pattern, a default or the underscore has no field to name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("fn %{id: id} -> id end")
      end
    end

    test "rejects a guard" do
      expected_msg =
        "lib/my_app/task_list.ex:7: the function of derived field :unread_count in MyApp.TaskList takes no guard, got: when channel != nil - its arguments name the fields it reads"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("fn channel when channel != nil -> channel end")
      end
    end

    test "rejects a guard on several arguments" do
      expected_msg =
        "lib/my_app/task_list.ex:7: the function of derived field :unread_count in MyApp.TaskList takes no guard, got: when channel != nil - its arguments name the fields it reads"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("fn channel, last_read_at when channel != nil -> channel end")
      end
    end

    test "rejects a default" do
      expected_msg =
        "lib/my_app/task_list.ex:7: the arguments of derived field :unread_count in MyApp.TaskList's function name fields, each a bare name, got: limit \\\\ 5 - a pattern, a default or the underscore has no field to name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("fn limit \\\\ 5 -> limit end")
      end
    end

    test "rejects a name written twice" do
      expected_msg =
        "lib/my_app/task_list.ex:7: channel is named twice in the head of derived field :unread_count in MyApp.TaskList's function - each argument names a field once"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("fn channel, channel -> channel end")
      end
    end

    test "rejects the underscore" do
      expected_msg =
        "lib/my_app/task_list.ex:7: the arguments of derived field :unread_count in MyApp.TaskList's function name fields, each a bare name, got: _ - a pattern, a default or the underscore has no field to name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_function("fn _ -> 1 end")
      end
    end
  end
end
