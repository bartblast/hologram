defmodule Hologram.Migration.CallCheckTest do
  use Hologram.Test.BasicCase, async: true

  @refusal_head "a migration may call only its own functions and the standard library's " <>
                  "functions that compute on the values they are given, like most of Kernel, " <>
                  "String, Enum, Map and Date - what it does to rows must never change after it " <>
                  "is applied, and the app's, its dependencies' and Hologram's modules change " <>
                  "with them, as do a module chosen at runtime, the clock, the environment and " <>
                  "random sources:\n"

  @compile_time_hint "\nAn op reading an attribute that holds a module uses the module at " <>
                       "compile time - if that is the case here, write the module in the op " <>
                       "itself."

  describe "validate!/2, a computed backfill" do
    test "passes the data form" do
      body = """
      change_entity MyApp.Task do
        add_attribute :city, :string, backfill: coalesce(title, ^String.upcase("none"))
      end
      """

      assert compile_migration("20260813091522", body)
    end

    test "refuses a refused call inside a pin" do
      body = """
      change_entity MyApp.Task do
        add_attribute :city, :string, backfill: coalesce(title, ^System.get_env("CITY"))
      end
      """

      error =
        assert_raise Hologram.CompileError, fn ->
          compile_migration("20260813091522", body)
        end

      assert error.message =~ "System.get_env/1"
    end

    test "refuses a refused call pinned as a separator" do
      body = """
      change_entity MyApp.Task do
        add_attribute :city, :string,
          backfill: title |> split(^System.get_env("SEPARATOR")) |> at(0)
      end
      """

      error =
        assert_raise Hologram.CompileError, fn ->
          compile_migration("20260813091522", body)
        end

      assert error.message =~ "System.get_env/1"
    end

    test "refuses a refused call pinned as a position" do
      body = """
      change_entity MyApp.Task do
        add_attribute :city, :string,
          backfill: title |> split(",") |> at(^System.schedulers())
      end
      """

      error =
        assert_raise Hologram.CompileError, fn ->
          compile_migration("20260813091522", body)
        end

      assert error.message =~ "System.schedulers/0"
    end
  end

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
      def count(list), do: {Enumerable.count(list), to_string(list), inspect(list)}

      # Field access, as on a map.
      def owner(opts), do: opts.owner

      defp log(message), do: Logger.debug(message)

      defp date, do: %Date{year: 2026, month: 8, day: 13}

      def unused, do: {&log/1, date(), &count/1, &owner/1}
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
          "  app/migrations/20260813091522.ex:8 - calls Hologram.Commons.StringUtils.prepend/2"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a call to Hologram.Migration, which only its use may require" do
      body = """
      def locals, do: Hologram.Migration.locals_without_parens()
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls Hologram.Migration.locals_without_parens/0"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a call to a module the code path does not hold" do
      body = """
      def code, do: MyApp.Missing.code()
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls MyApp.Missing.code/0"

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
          "  app/migrations/20260813091522.ex:4 - calls Hologram.Commons.StringUtils.prepend/2"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a struct outside the standard libraries" do
      body = """
      def server, do: %Hologram.Server{}
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - builds a %Hologram.Server{} struct"

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

    test "passes an attribute naming a module, read by a function" do
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
      @host URI.decode("example%2Ecom")

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
          "  app/migrations/20260813091522.ex:7 - builds a %Hologram.Server{} struct"

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
        @refusal_head <> "  app/migrations/20260813091522.ex:4 - calls #{inspect(other)}.code/0"

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
          "  app/migrations/20260813091522.ex:4 - calls Hologram.Server.__struct__/0\n" <>
          "  app/migrations/20260813091522.ex:5 - calls Hologram.Commons.StringUtils.prepend/2\n" <>
          "  app/migrations/20260813091522.ex:6 - calls Hologram.Server.__struct__/0"

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
          "  app/migrations/20260813091522.ex:5 - calls Hologram.Commons.StringUtils.prepend/2"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses apply/3 on a module chosen at runtime, naming its line" do
      body = """
      change_entity MyApp.Task do
        add_attribute :code, :string, default: code()
      end

      defp code, do: apply(Module.concat(["MyApp", "Defaults"]), :value, [])
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:8 - calls Module.concat/1\n" <>
          "  app/migrations/20260813091522.ex:8 - calls apply/3"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses apply/3 even on a standard library module" do
      body = """
      def code, do: apply(String, :upcase, ["a"])
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls apply/3"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a call on a module held in a variable" do
      body = """
      def code(module), do: module.value()
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls a function of a module known only at runtime"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a capture of a function on a module held in a variable" do
      body = """
      def code(module), do: &module.value/0
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls a function of a module known only at runtime"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses Function.capture/3 and a capture of apply" do
      body = """
      def capture(module), do: Function.capture(module, :value, 0)
      def dispatcher, do: &apply/3
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls Function.capture/3\n" <>
          "  app/migrations/20260813091522.ex:5 - calls apply/3"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses code evaluation" do
      body = """
      def eval(code), do: Code.eval_string(code)
      def template, do: EEx.eval_string("<%= 1 %>")
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls Code.eval_string/1\n" <>
          "  app/migrations/20260813091522.ex:5 - calls EEx.eval_string/1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses Kernel functions that reach a module given as a value" do
      body = """
      def build(module), do: struct(module, [])
      def exported?(module), do: function_exported?(module, :value, 0)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls Kernel.struct/2\n" <>
          "  app/migrations/20260813091522.ex:5 - calls :erlang.function_exported/3"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses :erlang functions beyond those that compute on values" do
      body = """
      def decode(binary), do: :erlang.binary_to_term(binary)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls :erlang.binary_to_term/1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses reading the clock, the environment, a random source or the node" do
      body = ~S"""
      def a, do: DateTime.utc_now()
      def b, do: Date.utc_today()
      def c, do: NaiveDateTime.local_now()
      def d, do: Time.utc_now()
      def e, do: System.get_env("HOME")
      def f, do: Application.get_env(:hologram, :env)
      def g, do: Enum.random([1, 2])
      def h, do: :rand.uniform()
      def i, do: {self(), make_ref(), node()}
      def j, do: :erlang.unique_integer()
      def k, do: :crypto.strong_rand_bytes(1)
      def l, do: String.to_existing_atom("a")
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls DateTime.utc_now/0\n" <>
          "  app/migrations/20260813091522.ex:5 - calls Date.utc_today/0\n" <>
          "  app/migrations/20260813091522.ex:6 - calls NaiveDateTime.local_now/0\n" <>
          "  app/migrations/20260813091522.ex:7 - calls Time.utc_now/0\n" <>
          "  app/migrations/20260813091522.ex:8 - calls System.get_env/1\n" <>
          "  app/migrations/20260813091522.ex:9 - calls Application.get_env/2\n" <>
          "  app/migrations/20260813091522.ex:10 - calls Enum.random/1\n" <>
          "  app/migrations/20260813091522.ex:11 - calls :rand.uniform/0\n" <>
          "  app/migrations/20260813091522.ex:12 - calls :erlang.make_ref/0\n" <>
          "  app/migrations/20260813091522.ex:12 - calls :erlang.node/0\n" <>
          "  app/migrations/20260813091522.ex:12 - calls :erlang.self/0\n" <>
          "  app/migrations/20260813091522.ex:13 - calls :erlang.unique_integer/0\n" <>
          "  app/migrations/20260813091522.ex:14 - calls :crypto.strong_rand_bytes/1\n" <>
          "  app/migrations/20260813091522.ex:15 - calls :erlang.binary_to_existing_atom/1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a function that calls a module given as a value or names the versions installed" do
      body = ~S"""
      def a(struct), do: Map.from_struct(struct)
      def b, do: Regex.version()
      def c(error), do: Exception.format(:error, error, [])
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls Map.from_struct/1\n" <>
          "  app/migrations/20260813091522.ex:5 - calls Regex.version/0\n" <>
          "  app/migrations/20260813091522.ex:6 - calls Exception.format/3"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses the URI functions and struct that follow the default port the app may set" do
      body = ~S"""
      def a(url), do: URI.parse(url).port
      def b(url), do: {URI.new(url), URI.new!(url)}
      def c(base, url), do: URI.merge(base, url)
      def d(uri), do: URI.to_string(uri)
      def e, do: %URI{scheme: "https", host: "example.com"}
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls URI.parse/1\n" <>
          "  app/migrations/20260813091522.ex:5 - calls URI.new!/1\n" <>
          "  app/migrations/20260813091522.ex:5 - calls URI.new/1\n" <>
          "  app/migrations/20260813091522.ex:6 - calls URI.merge/2\n" <>
          "  app/migrations/20260813091522.ex:7 - calls URI.to_string/1\n" <>
          "  app/migrations/20260813091522.ex:8 - builds a %URI{} struct"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses receiving a message" do
      body = ~S"""
      def next, do: receive(do: (message -> message), after: (0 -> :none))
      """

      expected_msg =
        @refusal_head <> "  app/migrations/20260813091522.ex:4 - receives a message"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a random source the module body used, though a function uses its module" do
      body = ~S"""
      @salt :crypto.strong_rand_bytes(4)

      change_entity MyApp.Task do
        add_attribute :salt, :string, default: Base.encode16(@salt)
      end

      def hash(text), do: :crypto.hash(:md5, text)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - uses :crypto at compile time, which can read " <>
          "the environment, the clock or a random source"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses the environment read in the module body" do
      body = ~S"""
      @home System.get_env("HOME")

      change_entity MyApp.Task do
        add_attribute :home, :string, default: @home
      end
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - uses System at compile time, which can read " <>
          "the environment, the clock or a random source"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses the date and time functions that read the time zone database" do
      body = ~S"""
      def a(naive), do: DateTime.from_naive!(naive, "Etc/UTC")
      def b(date, time), do: DateTime.new!(date, time)
      def c(datetime), do: DateTime.shift_zone!(datetime, "Europe/Warsaw")
      def d, do: DateTime.now!("Etc/UTC")
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls DateTime.from_naive!/2\n" <>
          "  app/migrations/20260813091522.ex:5 - calls DateTime.new!/2\n" <>
          "  app/migrations/20260813091522.ex:6 - calls DateTime.shift_zone!/2\n" <>
          "  app/migrations/20260813091522.ex:7 - calls DateTime.now!/1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a struct forged as a map, naming its module" do
      body = ~S"""
      def text, do: to_string(%{__struct__: MyApp.Thing, name: "a"})
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - builds a %MyApp.Thing{} struct"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses the rest of Kernel's functions that reach outside the migration" do
      body = ~S"""
      def a(module), do: struct!(module, [])
      def b(module), do: macro_exported?(module, :value, 0)
      def c(pid), do: send(pid, :value)
      def d, do: spawn(fn -> :ok end)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls Kernel.struct!/2\n" <>
          "  app/migrations/20260813091522.ex:5 - calls Kernel.macro_exported?/3\n" <>
          "  app/migrations/20260813091522.ex:6 - calls :erlang.send/2\n" <>
          "  app/migrations/20260813091522.ex:7 - calls :erlang.spawn/1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses Logger's configuration and exit/2" do
      body = ~S"""
      def translate, do: Logger.add_translator({:a, :b})
      def stop(pid), do: :erlang.exit(pid, :kill)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls Logger.add_translator/1\n" <>
          "  app/migrations/20260813091522.ex:5 - calls :erlang.exit/2"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses the standard functions that read atoms from text, return a module the app chose or read input" do
      body = ~S"""
      def a, do: :io_lib.fread(~c"~a", ~c"a")
      def b, do: Calendar.get_time_zone_database()
      def c, do: String.Chars.impl_for(1)
      def d, do: IO.gets("a")
      def e, do: IO.puts(:a_process, "a")
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls :io_lib.fread/2\n" <>
          "  app/migrations/20260813091522.ex:5 - calls Calendar.get_time_zone_database/0\n" <>
          "  app/migrations/20260813091522.ex:6 - calls String.Chars.impl_for/1\n" <>
          "  app/migrations/20260813091522.ex:7 - calls IO.gets/1\n" <>
          "  app/migrations/20260813091522.ex:8 - calls IO.puts/2"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a parse transform" do
      body = """
      @compile {:parse_transform, :ms_transform}
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - compiles through the transform :ms_transform"

      # Elixir warns that Erlang transforms are deprecated.
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_error Hologram.CompileError, expected_msg, fn ->
          compile_migration("20260813091522", body)
        end
      end)
    end

    test "passes a struct of the migration's own" do
      body = """
      defstruct [:code]

      def new(code), do: %__MODULE__{code: code}
      """

      assert compile_migration("20260813091522", body).new("a").code == "a"
    end

    test "compiles field access on a value into a strict map read" do
      body = """
      def name(row), do: row.name
      def city(row), do: put_in(row.address.city, "Warsaw").address.city
      """

      module = compile_migration("20260813091522", body)

      assert module.name(%{name: "a"}) == "a"
      struct = Map.put(~D[2026-01-01], :name, "b")

      assert module.name(struct) == "b"
      assert module.city(%{address: %{city: "Cracow"}}) == "Warsaw"

      assert_raise KeyError, fn -> module.name(%{}) end
      assert_raise BadMapError, fn -> module.name(Hologram.Test.Fixtures.Migration.Module1) end
    end

    test "compiles field access into a strict map read wherever Elixir allows it" do
      body = ~S"""
      defguard is_seven(row) when row.id == 7

      def path(row), do: get_in(row.a.b)
      def kernel_path(row), do: Kernel.put_in(row.a.b, 1).a.b
      def elixir_kernel_path(row), do: Elixir.Kernel.get_in(row.a.b)
      def bracket_path(row, item), do: put_in(row.items[item.id], :new).items
      def data(row), do: get_in(row.data, [:a])
      def average(rows), do: Enum.map(rows, &(&1.total / &1.count))
      def seven?(row) when is_seven(row), do: true
      def seven?(_row), do: false
      def body_seven?(row), do: is_seven(row)
      def piped_path(row), do: row.data |> get_in(row.path)
      def piped_put(row), do: row.data |> put_in(row.path, 9)
      def piped_macro(row), do: row.a.b |> put_in(2)
      def piped_update(row), do: row.a.b |> update_in(&(&1 + 1))
      def elixir_kernel_piped(row), do: row.a.b |> Elixir.Kernel.put_in(3)
      def receiver(receive), do: receive

      for field <- [:title] do
        def unquote(field)(row), do: row.unquote(field)
      end

      for module <- [:math] do
        def pi, do: unquote(module).pi
      end

      defmacro name_of(value), do: quote(do: unquote(value).name)

      def via_macro(row), do: name_of(row)

      defp name_code(value), do: quote(do: unquote(value).name)

      defmacrop name_through(value), do: name_code(value)

      def via_helper(row), do: name_through(row)

      defmacrop name_or_nil(value) do
        quote(do: unquote(value).name)
      rescue
        _error -> nil
      end

      def via_rescue(row), do: name_or_nil(row)

      defmacrop as_text, do: Macro.to_string(quote(do: x.y))

      def quoted_text, do: as_text()
      def quoted_code(row), do: Macro.to_string(quote(do: unquote(row.name)))

      defmacrop stringify(code), do: Macro.to_string(code)

      def stringified, do: stringify(x.y)
      def piped_stringified, do: x.y |> stringify()
      def bare_piped_stringified, do: x.y |> stringify
      def kernel_piped_stringified, do: Kernel.|>(x.y, stringify())

      def guarded(row) when stringify(row.y) == "row.y" and is_map(row), do: :ok
      def guarded(_row), do: :no

      def defaulted(text \\ stringify(x.y)), do: text

      defguardp stringified_guard(value) when stringify(value.y) == "value.y" and is_map(value)

      def via_guard(row) when stringified_guard(row), do: :ok
      def via_guard(_row), do: :no

      defmacrop twice(value), do: quote(do: unquote(value) <> unquote(value))

      def via_arg(row), do: twice(row.name)

      defp tier, unquote(do: "standard")

      def via_tier, do: tier()

      def unquoted_body(row), unquote([do: quote(do: var!(row).z)])

      def unquoted_rescue,
        unquote(do: quote(do: raise("x")), rescue: quote(do: (_error -> :rescued)))

      defmacrop unquoted_macro(value),
        unquote(do: quote(unquote: false, do: quote(do: unquote(var!(value)).z)))

      def via_unquoted_macro(row), do: unquoted_macro(row)
      """

      module = compile_migration("20260813091522", body)

      assert module.path(%{a: %{b: 1}}) == 1
      assert module.kernel_path(%{a: %{b: 0}}) == 1
      assert module.elixir_kernel_path(%{a: %{b: 4}}) == 4
      assert module.bracket_path(%{items: %{1 => :old}}, %{id: 1}) == %{1 => :new}
      assert module.data(%{data: %{a: 2}}) == 2
      assert module.average([%{total: 6, count: 3}]) == [2.0]
      assert module.seven?(%{id: 7})
      assert module.body_seven?(%{id: 7})
      assert module.piped_path(%{data: %{a: 1}, path: [:a]}) == 1
      assert module.piped_put(%{data: %{a: 1}, path: [:a]}) == %{a: 9}
      assert module.piped_macro(%{a: %{b: 1}}) == %{a: %{b: 2}}
      assert module.piped_update(%{a: %{b: 1}}) == %{a: %{b: 2}}
      assert module.elixir_kernel_piped(%{a: %{b: 1}}) == %{a: %{b: 3}}
      assert module.receiver(1) == 1
      assert module.title(%{title: "a"}) == "a"
      assert module.pi() == :math.pi()
      assert module.via_macro(%{name: "b"}) == "b"
      assert module.via_helper(%{name: "c"}) == "c"
      assert module.via_rescue(%{name: "d"}) == "d"
      assert module.quoted_text() == "x.y"
      assert module.quoted_code(%{name: "e"}) == ~s("e")
      assert module.stringified() == "x.y"
      assert module.piped_stringified() == "x.y"
      assert module.bare_piped_stringified() == "x.y"
      assert module.kernel_piped_stringified() == "x.y"
      assert module.guarded(%{}) == :ok
      assert module.defaulted() == "x.y"
      assert module.via_guard(%{}) == :ok
      assert module.via_arg(%{name: "f"}) == "ff"
      assert module.via_tier() == "standard"
      assert module.unquoted_body(%{z: 1}) == 1
      assert module.unquoted_rescue() == :rescued
      assert module.via_unquoted_macro(%{z: 2}) == 2

      assert_raise BadMapError, fn -> module.data(Hologram.Test.Fixtures.Migration.Module1) end

      assert_raise BadMapError, fn ->
        module.body_seven?(Hologram.Test.Fixtures.Migration.Module1)
      end

      assert_raise BadMapError, fn ->
        module.via_macro(Hologram.Test.Fixtures.Migration.Module1)
      end

      assert_raise BadMapError, fn ->
        module.via_helper(Hologram.Test.Fixtures.Migration.Module1)
      end

      assert_raise BadMapError, fn ->
        module.via_rescue(Hologram.Test.Fixtures.Migration.Module1)
      end

      assert_raise BadMapError, fn ->
        module.quoted_code(Hologram.Test.Fixtures.Migration.Module1)
      end

      assert_raise BadMapError, fn ->
        module.via_arg(Hologram.Test.Fixtures.Migration.Module1)
      end

      assert_raise BadMapError, fn -> module.title(Hologram.Test.Fixtures.Migration.Module1) end

      assert_raise BadMapError, fn ->
        module.unquoted_body(Hologram.Test.Fixtures.Migration.Module1)
      end

      assert_raise BadMapError, fn ->
        module.via_unquoted_macro(Hologram.Test.Fixtures.Migration.Module1)
      end
    end

    test "reads a pipe in a macro's code by the import it was written with" do
      body = ~S"""
      defmacrop piped_text, do: quote(do: Macro.to_string([do: x.y] |> quote()))

      import Kernel,
        except: [
          def: 1,
          def: 2,
          defguard: 1,
          defguardp: 1,
          defmacro: 1,
          defmacro: 2,
          defmacrop: 1,
          defmacrop: 2,
          defp: 1,
          defp: 2,
          |>: 2
        ]

      def left |> right, do: {left, right}

      def quoted_text, do: piped_text()
      """

      assert compile_migration("20260813091522", body).quoted_text() == "x.y"
    end

    test "reads a pipe into a quote in a macro's code by the import it was written with" do
      body = ~S"""
      defmacrop left |> right, do: {left, right}

      defmacrop bound(row), do: quote(do: [bind_quoted: [x: unquote(row).name]] |> quote(do: x))

      def name(row), do: bound(row)
      """

      module = compile_migration("20260813091522", body)

      code = module.name(%{name: "Alice"})

      assert {"Alice", _binding} = Code.eval_quoted(code)

      assert_raise BadMapError, fn -> module.name(Hologram.Test.Fixtures.Migration.Module1) end
    end

    test "passes a pipe to the migration's own pipe macro as written" do
      body = ~S"""
      import Kernel, only: []

      defmacrop left |> _right, do: Macro.to_string(left)

      def piped_text, do: [do: x.y] |> quote()
      """

      assert compile_migration("20260813091522", body).piped_text() == "[do: x.y]"
    end

    test "refuses the field access rewrite anywhere but around the code a macro returns" do
      body = """
      alias Hologram.Migration.FieldAccess.Definitions

      def rewritten(code, env), do: Definitions.__code__(code, env)

      defmacrop rewritten_text(code), do: Macro.to_string(Definitions.__code__(code, __CALLER__))

      defmacrop rewritten_in(code, env), do: Definitions.__code__(code, env)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:6 - calls " <>
          "Hologram.Migration.FieldAccess.Definitions.__code__/2\n" <>
          "  app/migrations/20260813091522.ex:8 - calls " <>
          "Hologram.Migration.FieldAccess.Definitions.__code__/2\n" <>
          "  app/migrations/20260813091522.ex:10 - calls " <>
          "Hologram.Migration.FieldAccess.Definitions.__code__/2"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "takes a path apart in an op, Kernel-qualified or piped" do
      body = """
      @config %{a: %{b: "x"}}

      change_entity MyApp.Task do
        add_attribute :code, :string, default: Kernel.get_in(@config.a.b)
        add_attribute :name, :string, default: (@config.a.b |> Kernel.put_in("y")).a.b
      end
      """

      assert [%{opts: [default: "x"]}, %{opts: [default: "y"]}] =
               compile_migration("20260813091522", body).__hologram_migration__().ops
    end

    test "compiles field access in an op into a strict map read" do
      body = """
      change_entity MyApp.Task do
        add_attribute :name, :string, default: holder().name
      end

      def holder, do: Hologram.Test.Fixtures.Migration.Module1
      """

      assert_raise BadMapError, fn -> compile_migration("20260813091522", body) end
    end

    test "refuses field access the strict map read did not reach" do
      body = """
      Kernel.def(value(module), do: module.value)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - reads a field outside the definitions use " <>
          "Hologram.Migration imports, where it could call a module's function"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a module defined besides the migration" do
      body = """
      defimpl String.Chars, for: Tuple do
        def to_string(_tuple), do: "tuple"
      end
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex - defines a module besides the migration"

      # Elixir warns that the consolidated protocol ignores the implementation.
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_error Hologram.CompileError, expected_msg, fn ->
          compile_migration("20260813091522", body)
        end
      end)
    end

    test "passes guards, macros, raise with a message held in a variable and reraise" do
      body = ~S"""
      defguardp is_even(x) when is_integer(x) and rem(x, 2) == 0

      defmacrop double(x), do: quote(do: unquote(x) * 2)

      def check(x) when is_even(x), do: double(x)

      def check(message) do
        raise message
      rescue
        error -> reraise error, __STACKTRACE__
      end
      """

      assert compile_migration("20260813091522", body).check(2) == 4
    end

    test "passes the other value modules and field access" do
      body = ~S"""
      def values(rows, row) do
        IO.inspect(row.id, label: "row")

        {Enum.map(rows, & &1.id), Function.identity(1), Duration.new!(day: 1),
         JSON.encode!(%{a: 1}), Date.range(~D[2026-01-01], ~D[2026-01-02]),
         :base64.encode("a"), :io_lib.format("~p", [1]), :crypto.hash(:sha256, "a"),
         Enum.sort(rows, :desc), String.to_atom("a"), :"Elixir.#{row.id}"}
      end

      def range?(%Date.Range{}), do: true
      """

      range = Date.range(~D[2026-01-01], ~D[2026-01-02])

      assert compile_migration("20260813091522", body).range?(range)
    end

    test "passes everyday code" do
      body = ~S"""
      require Logger

      @pattern ~r/^[a-z]+$/i

      change_entity MyApp.Task do
        add_attribute :code, :string, default: code("a, b")
      end

      defp code(text) do
        Logger.debug("code from #{text}")

        text
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.join()
      end

      def checks(x) when x in 1..5, do: for(i <- 1..x, i > 1, into: %{}, do: {i, i * 2})
      def member?(x, list), do: x in list and x not in Enum.reverse(list)
      def checks(x) when is_binary(x), do: raise(ArgumentError, "bad #{inspect(x)}")
      def checks(x), do: raise("bad #{x}")

      def values(t, m) do
        {elem(t, 0), put_elem(t, 0, 1), tuple_size(t), hd([1]), [1] ++ [2], map_size(m),
         get_in(m, [:a, :b]), put_in(m, [:a], 1), m[:z], %{m | a: 1}, m.a, @pattern,
         max(1, 2), div(4, 2), round(1.5), 2 ** 3, Bitwise.band(3, 1), "a" =~ @pattern}
      end

      def times do
        {~D[2026-01-01], ~U[2026-01-01 00:00:00Z], ~N[2026-01-01 00:00:00], ~T[10:00:00],
         Date.add(~D[2026-01-01], 1), DateTime.from_iso8601("2026-01-01T00:00:00Z"),
         DateTime.from_unix!(0), DateTime.add(~U[2026-01-01 00:00:00Z], 1, :day)}
      end

      def matches(value) do
        try do
          case value do
            %Date{} = date -> date
            <<"a", rest::binary>> -> rest
            [head | _tail] -> head
            {:ok, x} when x > 1 and not is_nil(x) -> to_string(x)
            _other -> Range.new(1, 3)
          end
        rescue
          error in ArgumentError -> Exception.message(error)
        end
      end

      def collections(list) do
        {MapSet.new(list), Keyword.get([a: 1], :a), Map.get(%{a: 1}, :a), List.flatten([list]),
         Tuple.to_list({1}), Integer.parse("1"), Float.round(1.25, 1), Atom.to_string(:a),
         Base.encode16("a"), URI.encode_www_form("a b"), Stream.map(list, & &1),
         :lists.reverse(list), :maps.keys(%{}), :binary.part("ab", 0, 1), :math.pow(2, 3),
         then(list, & &1), Enum.reduce(1..3//1, 0, &+/2), for(<<c <- "ab">>, do: c)}
      end
      """

      assert [%{opts: [default: "ab"]}] =
               compile_migration("20260813091522", body).__hologram_migration__().ops
    end
  end
end
