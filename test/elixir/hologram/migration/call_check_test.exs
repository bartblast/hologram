defmodule Hologram.Migration.CallCheckTest do
  use Hologram.Test.BasicCase, async: true

  @refusal_head "a migration may use only its own functions and the Elixir and Erlang/OTP " <>
                  "standard libraries - what it does to rows must never change after it is " <>
                  "applied, and the app's, its dependencies' and Hologram's modules change " <>
                  "with them:\n"

  @compile_time_hint "\nAn op reading an attribute that holds a module uses the module at " <>
                       "compile time - if that is the case here, write the module in the op " <>
                       "itself."

  describe "validate!/2" do
    test "passes a migration using Elixir's and Erlang's standard libraries and its own functions" do
      body = """
      require Logger

      change_entity MyApp.Task do
        add_attribute :code, :string, default: code()
      end

      defp code do
        "a, b"
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.join()
        |> then(&__MODULE__.suffix(&1, :erlang.phash2(&1)))
      end

      def suffix(code, hash), do: "\#{code}\#{Integer.to_string(:lists.max([hash, 0]))}"

      # Protocols Mix has consolidated load from the project's build dir.
      def count(list) do
        {Enumerable.count(list), to_string(list), Inspect.inspect(list, %Inspect.Opts{})}
      end

      defp log(message), do: Logger.debug(message)

      defp uri, do: %URI{host: "example.com"}

      defp eex, do: EEx.eval_string("<%= 1 %>")

      def unused, do: {&log/1, uri(), eex(), &count/1}
      """

      assert [%{op: :add_attribute}] =
               compile_migration("20260813091522", body).__hologram_migration__().ops
    end

    test "refuses a call to a module outside the standard libraries, naming its line" do
      body = """
      change_entity MyApp.Task do
        add_attribute :code, :string, default: code()
      end

      defp code, do: Hologram.Commons.StringUtils.prepend("a", "b")
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:8 - uses Hologram.Commons.StringUtils"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a call to Hologram.Migration, which only its use may require" do
      body = """
      def locals, do: Hologram.Migration.locals_without_parens()
      """

      expected_msg =
        @refusal_head <> "  app/migrations/20260813091522.ex:4 - uses Hologram.Migration"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a call to a module the code path does not hold, saying so" do
      body = """
      def code, do: MyApp.Missing.code()
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - uses MyApp.Missing, which is not compiled yet or cannot be found"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a capture of a function outside the standard libraries" do
      body = """
      def prepend, do: &Hologram.Commons.StringUtils.prepend/2
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - uses Hologram.Commons.StringUtils"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a struct outside the standard libraries" do
      body = """
      def server, do: %Hologram.Server{}
      """

      expected_msg =
        @refusal_head <> "  app/migrations/20260813091522.ex:4 - uses Hologram.Server"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a module-level require of a module outside the standard libraries" do
      body = """
      require Hologram.Commons.StringUtils
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - uses Hologram.Commons.StringUtils at compile time" <>
          @compile_time_hint

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses an attribute naming an entity type, read by an op" do
      body = """
      @entity MyApp.Task

      create_entity @entity
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - uses MyApp.Task at compile time, " <>
          "which is not compiled yet or cannot be found" <> @compile_time_hint

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses an attribute naming a module inside a value, read by an op" do
      body = """
      @defaults %{owner: MyApp.User}

      change_entity MyApp.Task do
        add_attribute :owner, :string, default: inspect(@defaults.owner)
      end
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - uses MyApp.User at compile time, " <>
          "which is not compiled yet or cannot be found" <> @compile_time_hint

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "passes an entity type named in an op" do
      body = """
      create_entity MyApp.Task
      """

      assert [%{op: :create_entity, entity: MyApp.Task}] =
               compile_migration("20260813091522", body).__hologram_migration__().ops
    end

    test "passes an entity type named through an alias in an op" do
      body = """
      alias MyApp.Task

      create_entity Task
      """

      assert [%{op: :create_entity, entity: MyApp.Task}] =
               compile_migration("20260813091522", body).__hologram_migration__().ops
    end

    test "passes an attribute naming a module, read only by a function" do
      body = """
      @entity MyApp.Task

      def entity, do: @entity
      """

      assert compile_migration("20260813091522", body).entity() == MyApp.Task
    end

    test "passes the standard libraries used in the module body, read by an op" do
      body = """
      import String, only: [upcase: 1]

      @pattern ~r/^[a-z]+$/
      @since %Date{year: 2026, month: 8, day: 13}
      @host URI.parse("https://example.com").host

      change_entity MyApp.Task do
        add_attribute :code, :string, default: upcase(@host)
        add_attribute :since, :date, default: @since
        add_attribute :slug, :string, format: @pattern
      end
      """

      assert [%{opts: [default: "EXAMPLE.COM"]}, %{opts: [default: ~D[2026-08-13]]}, _slug] =
               compile_migration("20260813091522", body).__hologram_migration__().ops
    end

    test "refuses a struct outside the standard libraries built in the module body" do
      body = """
      @server %Hologram.Server{}

      change_entity MyApp.Task do
        add_attribute :code, :string, default: inspect(@server)
      end
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - uses Hologram.Server at compile time" <>
          @compile_time_hint

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a call outside the standard libraries made in the module body" do
      body = """
      @default Hologram.Commons.StringUtils.prepend("a", "b")

      change_entity MyApp.Task do
        add_attribute :code, :string, default: @default
      end
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - uses Hologram.Commons.StringUtils at compile time" <>
          @compile_time_hint

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    # The compile-time check reads Kernel.LexicalTracker, Elixir's internal record of the
    # modules a module used while compiling. Should a release change it, this fails rather
    # than the check going quiet.
    test "sees the modules a migration used at compile time through Elixir's lexical tracker" do
      defmodule LexicalTrackerProbe do
        @moduledoc false

        # Runs in the compiling process, which Code.compile_string/1 makes this test's.
        @spec __after_compile__(Macro.Env.t(), binary) :: any
        def __after_compile__(env, _bytecode) do
          send(self(), {:references, Kernel.LexicalTracker.references(env.lexical_tracker)})
        end
      end

      Code.compile_string("""
      defmodule #{inspect(random_module())} do
        @after_compile #{inspect(LexicalTrackerProbe)}
        @value Hologram.Commons.StringUtils.prepend("a", "b")
        def value, do: @value
      end
      """)

      assert_received {:references, references}
      assert is_tuple(references) and tuple_size(references) >= 2
      assert Hologram.Commons.StringUtils in elem(references, 0)
    end

    test "refuses a call to another migration" do
      other = compile_migration("20260813091521", "def code, do: \"a\"")

      body = """
      def code, do: #{inspect(other)}.code()
      """

      expected_msg =
        @refusal_head <> "  app/migrations/20260813091522.ex:4 - uses #{inspect(other)}"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "names every refused reference once, in line order" do
      body = """
      def a, do: Hologram.Server.__struct__()
      def b, do: Hologram.Commons.StringUtils.prepend("a", "b")
      def c, do: Hologram.Server.__struct__()
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - uses Hologram.Server\n" <>
          "  app/migrations/20260813091522.ex:5 - uses Hologram.Commons.StringUtils\n" <>
          "  app/migrations/20260813091522.ex:6 - uses Hologram.Server"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a call before the ops are evaluated" do
      body = """
      change_entity MyApp.Task do
        add_attribute :code, :string, default: Hologram.Commons.StringUtils.prepend("a", "b")
      end
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:5 - uses Hologram.Commons.StringUtils"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end
end
