defmodule Hologram.Entity.DerivedExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.DerivedExpression

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53

  @field "derived field :unread_count in MyApp.Channel"

  @vocabulary_reason "a derived field is query vocabulary, evaluated by the database - Elixir over a row is a plain def in the module, called where the row is used"

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

    test "reports a local call that is no query stage as a query builder of the module's own" do
      {_names, _body, builder_call?} = lower("fn messages -> recent(messages) end")

      assert builder_call?
    end

    test "reports a zero-arity local call as a query builder of the module's own" do
      {_names, _body, builder_call?} = lower("fn -> featured() end")

      assert builder_call?
    end

    test "reports a local call the module imports from another module of the project as a query builder" do
      env = %{env() | functions: [{Module53, [member_messages: 1]}]}
      definition = Code.string_to_quoted!("fn member -> member_messages(member) end", line: 12)

      {_names, body, builder_call?} = function(:unread_count, definition, env)

      assert builder_call?

      assert Macro.to_string(body) ==
               normalize_newlines("""
               #{inspect(Module53)}.member_messages(
                 Derived.field(MyApp.Channel, [:member])
               )\
               """)
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

    test "raises on a local call into Kernel" do
      expected_msg = "lib/my_app/channel.ex:12: #{@field} calls length/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        lower("fn messages -> length(messages) end")
      end
    end

    test "raises on a query function the module imports that is no stage a derived body calls" do
      env = %{env() | functions: [{Hologram.Query, [trust: 1]}]}
      definition = Code.string_to_quoted!("fn messages -> trust(messages) end", line: 12)

      expected_msg = "lib/my_app/channel.ex:12: #{@field} calls trust/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        function(:unread_count, definition, env)
      end
    end

    test "raises on a query builder the module imports where a value goes" do
      env = %{env() | functions: [{Module53, [capitalized: 1]}]}
      definition = Code.string_to_quoted!("fn name -> name <> capitalized(name) end", line: 12)

      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls #{inspect(Module53)}.capitalized/1 where a value goes - a call to another module builds a query, so it stands where a query goes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        function(:unread_count, definition, env)
      end
    end

    test "raises on a query builder the module imports compared with a field" do
      env = %{env() | functions: [{Module53, [constant: 0]}]}
      definition = Code.string_to_quoted!("fn score -> score == constant() end", line: 12)

      expected_msg =
        "lib/my_app/channel.ex:12: #{@field} calls #{inspect(Module53)}.constant/0 where a value goes - a call to another module builds a query, so it stands where a query goes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        function(:unread_count, definition, env)
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

  describe "validate_own_builders!/1" do
    test "accepts a call to a function the module defines" do
      defmodule InlineEntityFixture165 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32
        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :channel, Module32, optional: true

        derived :recent, [Module33], fn channel -> recent(channel.messages) end

        @spec recent(Hologram.Query.t()) :: Hologram.Query.t()
        def recent(messages), do: Hologram.Query.take(messages, 2)
      end

      assert InlineEntityFixture165.__derived_builder_calls__() == [:recent]
    end

    test "accepts a call to a private function the module defines" do
      defmodule InlineEntityFixture166 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32
        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :channel, Module32, optional: true

        derived :recent, [Module33], fn channel -> recent(channel.messages) end

        defp recent(messages), do: Hologram.Query.take(messages, 2)
      end

      assert InlineEntityFixture166.__derived_builder_calls__() == [:recent]
    end

    test "raises on a call to a function the module doesn't define" do
      line = __ENV__.line + 14

      expected_msg =
        "#{Path.relative_to_cwd(__ENV__.file)}:#{line}: derived field :recent in Hologram.Entity.DerivedExpressionTest.InlineEntityFixture168 calls recent/1 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture168 do
          use Hologram.Entity

          alias Hologram.Test.Fixtures.Entity.Module32
          alias Hologram.Test.Fixtures.Entity.Module33

          relationship :channel, Module32, optional: true

          derived :recent, [Module33], fn channel -> recent(channel.messages) end
        end
      end
    end

    test "raises on a call to the module's own function where a value goes" do
      line = __ENV__.line + 12

      expected_msg =
        "#{Path.relative_to_cwd(__ENV__.file)}:#{line}: derived field :label in Hologram.Entity.DerivedExpressionTest.InlineEntityFixture169 calls suffix/1 where a value goes - a call to a query builder builds a query, so it stands where a query goes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture169 do
          use Hologram.Entity

          attribute :title, :string

          derived :label, :string, fn title ->
            title <> suffix(title)
          end

          defp suffix(_title), do: "!"
        end
      end
    end

    test "raises on a call to the module's own function compared with a field" do
      line = __ENV__.line + 11

      expected_msg =
        "#{Path.relative_to_cwd(__ENV__.file)}:#{line}: derived field :defaulted in Hologram.Entity.DerivedExpressionTest.InlineEntityFixture172 calls default_score/0 where a value goes - a call to a query builder builds a query, so it stands where a query goes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture172 do
          use Hologram.Entity

          attribute :score, :integer

          derived :defaulted, :boolean, fn score -> score == default_score() end

          defp default_score, do: 0
        end
      end
    end

    test "raises on a call compared with a field to a function the module doesn't define" do
      line = __ENV__.line + 11

      expected_msg =
        "#{Path.relative_to_cwd(__ENV__.file)}:#{line}: derived field :defaulted in Hologram.Entity.DerivedExpressionTest.InlineEntityFixture173 calls default_score/0 - #{@vocabulary_reason}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture173 do
          use Hologram.Entity

          attribute :score, :integer

          derived :defaulted, :boolean, fn score -> score == default_score() end
        end
      end
    end
  end

  describe "stages/0" do
    test "returns the stages a derived body may call, by arity" do
      assert stages() == [count: 1, filter: 2, include: 2, one: 1, skip: 2, sort: 2, take: 2]
    end
  end
end
