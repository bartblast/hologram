defmodule Hologram.Entity.DerivedExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.DerivedExpression

  @field "derived field :unread_count in MyApp.Channel"

  @vocabulary_reason "a derived field is query vocabulary, evaluated by the database - Elixir over a row is a plain def in the module"

  defp env do
    %{
      __ENV__
      | file: Path.join(File.cwd!(), "lib/my_app/channel.ex"),
        line: 7,
        module: MyApp.Channel
    }
  end

  defp lower(code) do
    definition = Code.string_to_quoted!(code, line: 12)

    function(:unread_count, definition, env())
  end

  describe "function/3" do
    test "returns the names the head binds" do
      {names, _body, _builder_call?} = lower("fn channel, last_read_at -> channel end")

      assert names == [:channel, :last_read_at]
    end

    test "reports a query builder called as the whole body" do
      {_names, _body, builder_call?} =
        lower("fn channel -> MyApp.Queries.unread_messages(channel) end")

      assert builder_call?
    end

    test "reports a query builder called as a pipe step" do
      {_names, _body, builder_call?} =
        lower("fn channel -> channel.messages |> MyApp.Queries.unread() |> take(5) end")

      assert builder_call?
    end

    test "reports a query builder called as a stage's source" do
      {_names, _body, builder_call?} =
        lower("fn channel -> count(MyApp.Queries.recent(channel.messages)) end")

      assert builder_call?
    end

    test "reports no query builder for a body of stages" do
      {_names, _body, builder_call?} = lower("fn messages -> count(messages) end")

      refute builder_call?
    end

    test "takes a negative number pinned in a query" do
      {names, _body, _builder_call?} =
        lower("fn messages -> filter(messages, position > ^-1) end")

      assert names == [:messages]
    end

    test "raises on a local binding" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} binds n - a derived field's body is one expression, with nothing bound along the way"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn messages -> (n = count(messages); n) end")
      end
    end

    test "raises on a call into Elixir's own modules" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls String.capitalize/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn name -> String.capitalize(name) end")
      end
    end

    test "raises on a call into an Erlang module" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls :math.pow/2 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score -> :math.pow(score, 2) end")
      end
    end

    test "raises at its line on a call into Elixir's own modules in a multi-line body" do
      expected_msg =
        "lib/my_app/channel.ex:13: #{@field} calls String.capitalize/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("""
        fn name ->
          String.capitalize(name)
        end
        """)
      end
    end

    test "raises on a call into Elixir's own modules in a condition" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls String.length/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score, nickname -> score > String.length(nickname) end")
      end
    end

    test "raises on a call on what is no module" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls score.round/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score -> score.round(1) end")
      end
    end

    test "raises on a query stage called through its module" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls Hologram.Query.count/1 - a derived field calls the query stages unqualified: count(...)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn messages -> Hologram.Query.count(messages) end")
      end
    end

    test "raises on a local call that is no query stage" do
      expected_msg = "lib/my_app/channel.ex:12: #{@field} calls recent/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn messages -> recent(messages) end")
      end
    end

    test "raises on a query builder where a value goes" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls MyApp.Queries.label/1 where a value goes - a call to another module builds a query, so it stands where a query goes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn name, channel -> name <> MyApp.Queries.label(channel) end")
      end
    end

    test "raises on a query of an entity type" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} reads MyApp.Message - a derived field's query starts from a relationship of the row, so write it through an argument"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn -> count(MyApp.Message) end")
      end
    end

    test "raises on a sigil" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} uses the sigil ~w - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn -> ~w(a b) end")
      end
    end

    test "raises on case" do
      expected_msg = "lib/my_app/channel.ex:12: #{@field} uses case - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score -> case score do 1 -> :one end end")
      end
    end

    test "raises on a comparison of what is no field" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} compares count(messages) - compare a derived field instead: declare count(messages) as one and read it here"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn messages -> count(messages) > 5 end")
      end
    end

    test "raises on a value on the left of a comparison" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} compares 0 on the left - a comparison reads a field on its left and what it is compared with on its right"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score -> 0 < score end")
      end
    end

    test "raises on a comparison with what is no value or field" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} compares with count(messages) - the other side of a comparison is a value, an @attribute or a field"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score, messages -> score > count(messages) end")
      end
    end

    test "raises at the membership's line on a list holding a field" do
      expected_msg =
        "lib/my_app/channel.ex:13: #{@field} looks a field up in [1, other] - the right side of in is a list of values or an @attribute"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("""
        fn score, other ->
          score in [1, other]
        end
        """)
      end
    end

    test "raises on a condition joining what is no comparison" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} joins starts_with(nickname, \"a\") into a condition - a condition compares fields with ==, !=, <, <=, >, >=, in and not in, joined by and and or"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower(~s[fn score -> score > 1 and starts_with(nickname, "a") end])
      end
    end

    test "raises on if branching on what is no condition" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} branches on score - the condition of if compares fields with ==, !=, <, <=, >, >=, in and not in, joined by and and or"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score -> if score, do: 1, else: 2 end")
      end
    end

    test "raises on if with an option other than do and else" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} uses if with [do: 1, after: 2] - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn score -> if score > 1, do: 1, after: 2 end")
      end
    end

    test "raises on a body of several expressions" do
      expected_msg =
        "lib/my_app/channel.ex:13: #{@field} has a body of 2 expressions - a derived field's body is one expression"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("""
        fn messages ->
          count(messages)
          one(messages)
        end
        """)
      end
    end

    test "raises on a condition where a value goes" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} holds the condition name == \"x\" where a value goes - a condition stands as the whole body or as the condition of if"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower(~s[fn name -> name <> (name == "x") end])
      end
    end

    test "raises on a list outside in" do
      expected_msg =
        "lib/my_app/channel.ex:7: #{@field} holds the list [1, 2] - a list of values stands only on the right side of in"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn -> [1, 2] end")
      end
    end

    test "raises on a pinned value that is no field, attribute or literal" do
      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} pins length(names) - a pinned value in a derived field's query is an argument, a chain on one, an @attribute or a literal"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn messages, names -> filter(messages, position > ^length(names)) end")
      end
    end

    test "raises at the head on a name no argument binds" do
      expected_msg =
        "lib/my_app/channel.ex:12: messages is not an argument of the function of #{@field} - add it to the head to read the field"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("""
        fn channel ->
          count(messages)
        end
        """)
      end
    end
  end

  describe "stages/0" do
    test "returns the stages a derived body may call, by arity" do
      assert stages() == [count: 1, filter: 2, include: 2, one: 1, skip: 2, sort: 2, take: 2]
    end
  end
end
