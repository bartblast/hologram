defmodule Hologram.Migration.CallCheckTest do
  use Hologram.Test.BasicCase, async: true

  @refusal_head "a migration may call only its own functions and the standard library's " <>
                  "modules that work on values, like Kernel, String, Enum, Map and Date, and " <>
                  "may hold no other module than the entity types and roles its ops name - " <>
                  "what it does to rows must never change after it is applied, and the app's, " <>
                  "its dependencies' and Hologram's modules change with them, as does a " <>
                  "module chosen at runtime:\n"

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
      def count(list), do: {Enumerable.count(list), to_string(list), inspect(list)}

      # Field access, as on a map.
      def owner(opts), do: opts.owner

      defp log(message), do: Logger.debug(message)

      defp uri, do: %URI{host: "example.com"}

      def unused, do: {&log/1, uri(), &count/1, &owner/1}
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
          "  app/migrations/20260813091522.ex:7 - holds the module MyApp.User"

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

    test "refuses an attribute naming a module, read by a function" do
      body = """
      @entity MyApp.Task

      def entity, do: @entity
      """

      expected_msg =
        @refusal_head <> "  app/migrations/20260813091522.ex:6 - holds the module MyApp.Task"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
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

    test "refuses a module given to a standard function as a value" do
      body = ~S"""
      def sorted(list), do: Enum.sort(list, MyApp.Order)
      def date, do: Date.new(2026, 1, 1, MyApp.Calendar)
      def now, do: DateTime.now("Europe/Warsaw", MyApp.TimeZoneDatabase)
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - holds the module MyApp.Order\n" <>
          "  app/migrations/20260813091522.ex:5 - holds the module MyApp.Calendar\n" <>
          "  app/migrations/20260813091522.ex:6 - holds the module MyApp.TimeZoneDatabase"

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

    test "refuses building an atom from a string" do
      body = ~S"""
      def atom(name), do: String.to_atom(name)
      def existing(name), do: List.to_existing_atom(name)
      def interpolated(name), do: :"Elixir.#{name}"
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - calls :erlang.binary_to_atom/1\n" <>
          "  app/migrations/20260813091522.ex:5 - calls :erlang.list_to_existing_atom/1\n" <>
          "  app/migrations/20260813091522.ex:6 - calls :erlang.binary_to_atom/2"

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

    test "refuses a module held in a macro" do
      body = ~S"""
      defmacro order, do: MyApp.Order
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:4 - holds the module MyApp.Order"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses reading the migration's own ops back" do
      body = ~S"""
      create_entity MyApp.Order

      def order, do: __hologram_migration__()
      def capture, do: &__hologram_migration__/0
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:6 - reads the migration's own ops\n" <>
          "  app/migrations/20260813091522.ex:7 - reads the migration's own ops"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses modules named in an op outside its entity type fields" do
      body = ~S"""
      change_entity MyApp.Task do
        add_attribute :code, :string, default: MyApp.Order
        add_attribute :name, :string, default: inspect(%{op: :forged, entity: MyApp.Order}.entity)
      end
      """

      expected_msg =
        @refusal_head <>
          "  app/migrations/20260813091522.ex:5 - holds the module MyApp.Order\n" <>
          "  app/migrations/20260813091522.ex:6 - holds the module MyApp.Order"

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

    test "refuses a struct of the migration's own" do
      body = """
      defstruct [:code]
      """

      %{message: message} =
        assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

      assert message =~ "app/migrations/20260813091522.ex:4 - builds a %"
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

    test "refuses reading the migration's own ops back through the module" do
      body = """
      create_entity MyApp.Order

      def remote, do: __MODULE__.__hologram_migration__()
      def field(module), do: module.__hologram_migration__
      """

      %{message: message} =
        assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

      assert message =~ ~r"ex:6 - calls .*V20260813091522\.__hologram_migration__/0\n"
      assert message =~ "ex:7 - reads the migration's own ops"
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
         Version.parse!("1.0.0"), JSON.encode!(%{a: 1}), Date.range(~D[2026-01-01], ~D[2026-01-02]),
         :base64.encode("a"), :calendar.valid_date(2026, 1, 1), :io_lib.format("~p", [1]),
         :crypto.hash(:sha256, "a"), self(), make_ref(), node()}
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
         Calendar.ISO.valid_date?(2026, 1, 1)}
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
         Base.encode16("a"), URI.parse("https://example.com").host, Stream.map(list, & &1),
         :lists.reverse(list), :maps.keys(%{}), :binary.part("ab", 0, 1), :math.pow(2, 3),
         then(list, & &1), Enum.reduce(1..3//1, 0, &+/2), for(<<c <- "ab">>, do: c)}
      end
      """

      assert [%{opts: [default: "ab"]}] =
               compile_migration("20260813091522", body).__hologram_migration__().ops
    end
  end
end
