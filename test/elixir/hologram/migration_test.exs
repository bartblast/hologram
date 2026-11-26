defmodule Hologram.MigrationTest.AliasReferenceTracer do
  @moduledoc false

  # Reports to the compiling process each reference to the traced alias, with the function
  # it is made from - nil for a module-body reference, which is a compile-time dependency.
  @spec trace(tuple | atom, Macro.Env.t()) :: :ok
  def trace({:alias_reference, _meta, Hologram.MigrationTest.Traced = module}, env) do
    send(self(), {:alias_reference, module, env.function})
    :ok
  end

  def trace(_event, _env), do: :ok
end

defmodule Hologram.MigrationTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration

  alias Hologram.Migration.Value
  alias Hologram.MigrationTest.AliasReferenceTracer

  defp ops(body) do
    "20260813091522"
    |> compile_migration(body)
    |> then(& &1.__hologram_migration__().ops)
  end

  describe "__after_compile__/2" do
    test "rejects a module referencing an entity by its pre-rename name" do
      body = """
      rename_entity MyApp.Old, MyApp.New

      change_entity MyApp.Old do
        add_attribute :title, :string
      end
      """

      expected_msg =
        "app/migrations/20260813091522.ex:7 references MyApp.Old, renamed on line 4 - " <>
          "move the rename first and use MyApp.New"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a backfill naming a function of the module the backfill didn't generate" do
      body = """
      def opts do
        value = %Hologram.Migration.Value{
          args: [:status],
          term: {:function, __MODULE__, :module_info, [:status]}
        }

        [backfill: value]
      end

      change_entity MyApp.Trip do
        add_attribute :value, :string, opts()
      end
      """

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a module body setting the list of generated backfill functions" do
      body = """
      @__hologram_migration_backfill_functions__ [{__MODULE__, :module_info, [:status]}]

      def opts do
        value = %Hologram.Migration.Value{
          args: [:status],
          term: {:function, __MODULE__, :module_info, [:status]}
        }

        [backfill: value]
      end

      change_entity MyApp.Trip do
        add_attribute :value, :string, opts()
      end
      """

      assert_raise Hologram.CompileError, ~r/is the attribute Hologram lists the functions/, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "refuses a module body making the list of generated backfill functions accumulate" do
      body = """
      Module.register_attribute(__MODULE__, :__hologram_migration_backfill_functions__,
        accumulate: true
      )

      @__hologram_migration_backfill_functions__ {__MODULE__, :module_info, [:status]}

      def opts do
        value = %Hologram.Migration.Value{
          args: [:status],
          term: {:function, __MODULE__, :module_info, [:status]}
        }

        [backfill: value]
      end

      change_entity MyApp.Trip do
        add_attribute :value, :string, opts()
      end
      """

      assert_raise Hologram.CompileError, ~r/is the attribute Hologram lists the functions/, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "fails the build when an op cannot be evaluated" do
      body = """
      change_entity MyApp.Task do
        add_attribute :count, :integer, default: String.to_integer("x")
      end
      """

      assert_raise ArgumentError, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end

  describe "__before_compile__/1" do
    test "refuses an Elixir backfill fn reading an attribute in code that never runs" do
      body = """
      @suffix "!"

      if false do
        change_entity MyApp.Task do
          add_attribute :first, :string, backfill: fn title -> title <> @suffix end
        end
      end
      """

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise Hologram.CompileError, ~r/reads @suffix/, fn ->
          compile_migration("20260813091522", body)
        end
      end)
    end

    test "refuses an op that reads an attribute in module-body code that never runs" do
      body = """
      @default "a"

      if false do
        change_entity MyApp.Task do
          add_attribute :first, :string, default: @default
        end
      end
      """

      expected_msg =
        "a migration op reads an attribute in module-body code that never runs, so the op " <>
          "would record nil for it - ops are recorded wherever they are written, so write " <>
          "them outside if, case and the like:\n" <>
          "  app/migrations/20260813091522.ex:8 - reads @default"

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_error Hologram.CompileError, expected_msg, fn ->
          compile_migration("20260813091522", body)
        end
      end)
    end
  end

  describe "__hologram_migration__/0" do
    test "returns the version, the path and the ops of the module body, in file order" do
      module =
        compile_migration("20260813091522", """
        create_entity MyApp.Task do
          add_attribute :title, :string
        end

        delete_entity MyApp.Archive
        """)

      assert module.__hologram_migration__() == %{
               version: "20260813091522",
               path: "app/migrations/20260813091522.ex",
               ops: [
                 %{op: :create_entity, entity: MyApp.Task, line: 4},
                 %{
                   op: :add_attribute,
                   entity: MyApp.Task,
                   name: :title,
                   type: :string,
                   opts: [],
                   line: 5
                 },
                 %{op: :delete_entity, entity: MyApp.Archive, line: 8}
               ]
             }
    end

    test "returns no ops for a module without any" do
      module = compile_migration("20260813091522", "")

      assert module.__hologram_migration__().ops == []
    end

    test "keeps a regex option" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Task do
          add_attribute :code, :string, format: ~r/^[A-Z]+$/i
        end
        """)

      assert [%{opts: [format: regex]}] = module.__hologram_migration__().ops
      assert Regex.source(regex) == "^[A-Z]+$"
      assert Regex.opts(regex) == [:caseless]
    end

    test "resolves an alias where the op is written, not where the module ends" do
      module =
        compile_migration("20260813091522", """
        alias MyApp.Short

        create_entity Short

        alias MyApp.Long.Short

        delete_entity Short
        """)

      assert [first, second] = module.__hologram_migration__().ops
      assert first.entity == MyApp.Short
      assert second.entity == MyApp.Long.Short
    end

    test "returns the flat ops of every kind" do
      module =
        compile_migration("20260813091522", """
        add_role MyApp.Roles.Admin
        change_role MyApp.Roles.Admin, extends: MyApp.Roles.Member
        rename_role MyApp.Roles.Admin, MyApp.Roles.Owner
        delete_role MyApp.Roles.Guest
        designate_user_entity MyApp.User
        delete_role_grants()
        rename_entity MyApp.Old, MyApp.New
        resolve! :entities, deleted: [MyApp.Gone], added: [MyApp.Came]
        """)

      assert module.__hologram_migration__().ops == [
               %{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 4},
               %{
                 op: :change_role,
                 role: MyApp.Roles.Admin,
                 changes: [extends: MyApp.Roles.Member],
                 line: 5
               },
               %{op: :rename_role, from: MyApp.Roles.Admin, to: MyApp.Roles.Owner, line: 6},
               %{op: :delete_role, role: MyApp.Roles.Guest, line: 7},
               %{op: :designate_user_entity, entity: MyApp.User, line: 8},
               %{op: :delete_role_grants, line: 9},
               %{op: :rename_entity, from: MyApp.Old, to: MyApp.New, line: 10},
               %{
                 op: :resolve!,
                 kind: :entities,
                 payload: [deleted: [MyApp.Gone], added: [MyApp.Came]],
                 line: 11
               }
             ]
    end

    test "returns the op removing the user entity designation" do
      assert ops("designate_user_entity nil") == [
               %{op: :designate_user_entity, entity: nil, line: 4}
             ]
    end

    test "returns a resolve! op inside an entity block" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Task do
          resolve! :fill, attributes: [:title]
        end
        """)

      assert module.__hologram_migration__().ops == [
               %{
                 op: :resolve!,
                 entity: MyApp.Task,
                 kind: :fill,
                 payload: [attributes: [:title]],
                 line: 5
               }
             ]
    end

    test "evaluates op arguments that call the module's functions and read its attributes" do
      module =
        compile_migration("20260813091522", """
        @status_default :draft

        change_entity MyApp.Task do
          add_attribute :status, :atom, default: @status_default
          add_attribute :code, :string, default: code_default()
        end

        defp code_default, do: "A1"
        """)

      assert [%{opts: [default: :draft]}, %{opts: [default: "A1"]}] =
               module.__hologram_migration__().ops
    end

    test "reads an attribute where the op is written, not where the module ends" do
      module =
        compile_migration("20260813091522", """
        @default "a"

        change_entity MyApp.Task do
          add_attribute :first, :string, default: @default
        end

        @default "b"

        change_entity MyApp.Task do
          add_attribute :second, :string, default: @default
        end
        """)

      assert [%{opts: [default: "a"]}, %{opts: [default: "b"]}] =
               module.__hologram_migration__().ops
    end

    test "warns about an attribute an op reads before it is set" do
      body = """
      change_entity MyApp.Task do
        add_attribute :first, :string, default: @later
      end

      @later "b"
      """

      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          module = compile_migration("20260813091522", body)

          send(self(), {:ops, module.__hologram_migration__().ops})
        end)

      assert output =~ "undefined module attribute @later"
      assert output =~ "app/migrations/20260813091522.ex:5"
      assert_received {:ops, [%{opts: [default: nil]}]}
    end

    test "reads an attribute written with parentheses where the op is written" do
      body = """
      @default "a"

      change_entity MyApp.Task do
        add_attribute :first, :string, default: @default()
      end

      @default "b"
      """

      # The parentheses notation is deprecated, and Elixir warns about it.
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        module = compile_migration("20260813091522", body)

        send(self(), {:ops, module.__hologram_migration__().ops})
      end)

      assert_received {:ops, [%{opts: [default: "a"]}]}
    end

    test "reads an attribute a quote runs where the op is written" do
      for {backfill, value} <- [
            {"fn title -> inspect(quote(bind_quoted: [x: @o], do: x)) <> title end", ~s("1")},
            {"fn title -> inspect([bind_quoted: [x: @o], do: x] |> quote()) <> title end",
             ~s("1")},
            {"fn title -> coalesce(title, ^inspect(quote(do: unquote(@o)))) end", ~s("1")},
            # A bare atom in the option list sets its option to true, and the first one counts.
            {"fn title -> coalesce(title, ^inspect(quote([:unquote, unquote: false], " <>
               "do: unquote(@o)))) end", ~s("1")},
            # A quote's separate options are code even in a quote of a quote.
            {"fn title -> coalesce(title, ^inspect(quote(do: quote(unquote(@o), do: 1)))) end",
             ~s("1")},
            {"fn title -> coalesce(title, ^inspect([] |> quote(do: unquote(@o)))) end", ~s("1")}
          ] do
        module =
          compile_migration("20260813091522", """
          @o "1"

          change_entity MyApp.Task do
            add_attribute :first, :string, backfill: #{backfill}
          end

          @o "2"

          change_entity MyApp.Task do
            add_attribute :second, :string, default: @o
          end
          """)

        assert [%{opts: [backfill: backfill_value]}, %{opts: [default: "2"]}] =
                 module.__hologram_migration__().ops

        result =
          case backfill_value.term do
            {:function, ^module, name, [:title]} -> apply(module, name, [""])
            {:coalesce, [{:name, [:title]}, {:value, result}]} -> result
          end

        assert result =~ value
        refute result =~ ~s("2")
      end
    end

    test "reads an attribute in a quote's option list where the op is written" do
      for quoted <- ["quote([@opts, do: x])", "[@opts, do: x] |> quote()"] do
        module =
          compile_migration("20260813091522", """
          @opts {:bind_quoted, [x: "early"]}

          change_entity MyApp.Task do
            add_attribute :first, :string,
              backfill: fn title -> coalesce(title, ^inspect(#{quoted})) end
          end

          @opts {:bind_quoted, [x: "late"]}

          change_entity MyApp.Task do
            add_attribute :second, :string, default: inspect(@opts)
          end
          """)

        assert [%{opts: [backfill: %{term: {:coalesce, [_title, {:value, result}]}}]}, _second] =
                 module.__hologram_migration__().ops

        assert result =~ "early"
        refute result =~ "late"
      end
    end

    test "leaves an attribute in a quote's body as data, piped or not" do
      for quoted <- [
            "quote(do: @o)",
            "[do: @o] |> quote()",
            "quote(do: quote(do: unquote(@o)))",
            "quote(unquote: false, do: unquote(@o))",
            # Left of the pipe are the quote's separate options.
            "[unquote: false] |> quote(do: unquote(@o))",
            "Kernel.|>([bind_quoted: [y: 2]], quote(do: unquote(@o)))",
            # The function splices nothing in code a quote runs, so a quote piped there follows
            # its own options.
            "quote(do: unquote([unquote: false, do: unquote(@o)] |> quote()))",
            "quote(do: unquote([bind_quoted: [y: 1], do: unquote(@o)] |> quote()))",
            "quote(bind_quoted: [x: [unquote: false, do: unquote(@o)] |> quote()], do: x)",
            # A pipe on the right side is the stages after the left side, the first a quote.
            "[do: @o] |> (quote() |> inspect())",
            "Kernel.|>([do: @o], quote() |> inspect())",
            # So is Kernel's pipe given only a stage.
            "[do: @o] |> Kernel.|>(quote())",
            "[unquote: false] |> Kernel.|>(quote(do: unquote(@o)))"
          ] do
        module =
          compile_migration("20260813091522", """
          change_entity MyApp.Task do
            add_attribute :first, :string, backfill: fn title -> coalesce(title, ^inspect(#{quoted})) end
          end
          """)

        assert [%{opts: [backfill: %{term: {:coalesce, [{:name, [:title]}, {:value, result}]}}]}] =
                 module.__hologram_migration__().ops

        assert result =~ "{:o, "
        refute result =~ "__hologram_migration_"
      end
    end

    test "refuses an attribute a quote unquotes under options only the compiler can read" do
      for quoted <- ["quote(@opts, do: unquote(@o))", "@opts |> quote(do: unquote(@o))"] do
        body = """
        @opts []
        @o "1"

        change_entity MyApp.Task do
          add_attribute :first, :string,
            backfill: fn title -> coalesce(title, ^inspect(#{quoted})) end
        end
        """

        error =
          assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

        assert error.message ==
                 "an op can't unquote @o in a quote whose options only the compiler can read, " <>
                   "like an attribute (line 9) - write the options out, or don't unquote the " <>
                   "attribute"
      end
    end

    test "refuses an attribute a quote unquotes under an option an attribute in its list sets" do
      for {opts, quoted} <- [
            {"{:unquote, true}", "quote([@opts, bind_quoted: [x: 1], do: unquote(@o)])"},
            {"{:unquote, false}", "quote([@opts, do: unquote(@o)])"}
          ] do
        body = """
        @opts #{opts}
        @o "1"

        change_entity MyApp.Task do
          add_attribute :first, :string,
            backfill: fn title -> coalesce(title, ^inspect(#{quoted})) end
        end
        """

        error =
          assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

        assert error.message ==
                 "an op can't unquote @o in a quote whose options only the compiler can read, " <>
                   "like an attribute (line 9) - write the options out, or don't unquote the " <>
                   "attribute"
      end
    end

    test "reads an attribute a quote unquotes under an unquote written before an attribute in its list" do
      module =
        compile_migration("20260813091522", """
        @opts {:unquote, false}
        @o "early"

        change_entity MyApp.Task do
          add_attribute :first, :string,
            backfill: fn title ->
              coalesce(title, ^inspect(quote([{:unquote, true}, @opts, {:do, unquote(@o)}])))
            end
        end

        @o "late"

        change_entity MyApp.Task do
          add_attribute :second, :string, default: @o
        end
        """)

      assert [%{opts: [backfill: %{term: {:coalesce, [_title, {:value, result}]}}]}, _second] =
               module.__hologram_migration__().ops

      assert result == inspect("early")
    end

    test "refuses an unquote the function an op is compiled into splices in" do
      pins = [
        "unquote(quote(do: @o))",
        "unquote(@ast)",
        "[unquote: false, do: unquote(@o)] |> quote()",
        "[bind_quoted: [y: 1], do: unquote(title)] |> quote()",
        "Kernel.|>([do: unquote(@o)], quote())",
        "[do: String.unquote(@fun)(1)] |> quote()",
        # The function splices in a quote's separate options when it has another unquote, which
        # another op can add.
        "quote([bind_quoted: [x: unquote(@o)]], do: x)",
        "quote([bind_quoted: [x: [do: unquote(@o)] |> quote()]], do: x)",
        "[do: quote([bind_quoted: [x: unquote(@o)]], do: x)] |> quote()",
        "[unquote: false, do: quote(unquote(@o), do: 1)] |> quote()"
      ]

      elixir_bodies = [
        "unquote(@o) <> title",
        "String.unquote(@fun)(title)",
        "title |> String.unquote(@fun)",
        "Kernel.|>(title, String.unquote(@fun))",
        "inspect([do: unquote(title)] |> quote()) <> title"
      ]

      options =
        ["default: unquote(@o)"] ++
          Enum.map(pins, &"backfill: fn title -> coalesce(title, ^inspect(#{&1})) end") ++
          Enum.map(elixir_bodies, &"backfill: fn title -> #{&1} end")

      for {option, form} <- [
            {"default: [unquote_splicing([@o])]", :unquote_splicing},
            {"backfill: fn title -> Enum.join([unquote_splicing([@o]), title]) end",
             :unquote_splicing}
            | Enum.map(options, &{&1, :unquote})
          ] do
        body = """
        @ast quote(do: @o)
        @fun :upcase
        @o "1"

        change_entity MyApp.Task do
          add_attribute :first, :string, #{option}
        end
        """

        error =
          assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

        assert error.message ==
                 "an op can't #{form} where the function it's compiled into may splice the " <>
                   "code in, like outside a quote, in a body piped into one or in a quote's " <>
                   "separate options (line 9) - write @x for a value of the file, or put a " <>
                   "quote's body in its parentheses"
      end
    end

    test "refuses an alias the op's code declares" do
      pin = &"backfill: fn title -> coalesce(title, ^#{&1}) end"
      declared = ~s[alias String, as: Lib; Lib.reverse("abc")]

      for {option, form} <- [
            {pin.("(#{declared})"), :alias},
            {pin.(~s[(alias String; Lib.reverse("abc"))]), :alias},
            {pin.(~s[(alias String.{Chars}; Lib.reverse("abc"))]), :alias},
            {pin.(~s[(require String, as: Lib; Lib.reverse("abc"))]), :require},
            # Options not written out may hold as:.
            {pin.(~s[(require String, @o; Lib.reverse("abc"))]), :require},
            {pin.("inspect(quote(do: unquote((#{declared}))))"), :alias},
            {pin.("inspect(quote(bind_quoted: [x: (#{declared})], do: x))"), :alias},
            # Options only the compiler can read may let the unquote run.
            {pin.("inspect(quote(@opts, do: unquote((#{declared}))))"), :alias},
            {"backfill: fn title -> (alias String, as: Lib; Lib.reverse(title)) end", :alias},
            {"default: (#{declared})", :alias}
          ] do
        body = """
        @o [as: Lib]
        @opts []
        alias Enum, as: Lib
        change_entity MyApp.Task do
          add_attribute :first, :string, #{option}
        end
        """

        error =
          assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

        assert error.message ==
                 "an op can't declare an alias inside its code - put the #{form} at the top of " <>
                   "the module"

        assert error.line == 8
      end
    end

    test "keeps a require that declares no alias, and what only looks like an alias" do
      body = """
      change_entity MyApp.Task do
        add_attribute :first, :string,
          backfill: fn title -> coalesce(title, ^(require Integer; inspect(Integer.is_even(2)))) end

        add_attribute :second, :string,
          backfill: fn title -> coalesce(title, ^inspect(quote(do: alias(String, as: Lib)))) end

        add_attribute :third, :string, default: (alias = "a"; alias)
        add_attribute :fourth, :string, default: inspect(%{alias: 1}.alias)

        add_attribute :fifth, :string,
          backfill: fn title -> coalesce(title, ^(require Integer, warn: false; "a")) end
      end
      """

      module = compile_migration("20260813091523", body)

      assert [first, second, third, fourth, fifth] = module.__hologram_migration__().ops

      assert %{name: :first, opts: [backfill: %Value{term: {:coalesce, [_title, value: "true"]}}]} =
               first

      assert %{
               name: :second,
               opts: [backfill: %Value{term: {:coalesce, [_title, value: quoted]}}]
             } =
               second

      assert quoted =~
               ~s({:alias, [context: #{inspect(module)}], [{:__aliases__, [alias: false], [:String]})

      assert %{name: :third, opts: [default: "a"]} = third
      assert %{name: :fourth, opts: [default: "1"]} = fourth

      assert %{name: :fifth, opts: [backfill: %Value{term: {:coalesce, [_title, value: "a"]}}]} =
               fifth
    end

    test "keeps an alias a quote takes from a pipe on a pipe's right side" do
      for default <- [
            "[do: (alias String, as: Lib)] |> (quote() |> Macro.to_string())",
            "Macro.to_string([do: (alias String, as: Lib)] |> Kernel.|>(quote()))"
          ] do
        body = """
        change_entity MyApp.Task do
          add_attribute :first, :string, default: #{default}
        end
        """

        module = compile_migration("20260813091522", body)

        assert [%{op: :add_attribute, opts: opts}] = module.__hologram_migration__().ops
        assert opts[:default] == "alias String, as: Lib"
      end
    end

    test "keeps an alias in a do that a quote with separate options ignores" do
      body = """
      change_entity MyApp.Task do
        add_attribute :first, :string,
          default: Macro.to_string(quote([], [do: :standard, do: unquote((alias String, as: Lib))]))
      end
      """

      module = compile_migration("20260813091522", body)

      assert [%{op: :add_attribute, opts: opts}] = module.__hologram_migration__().ops
      assert opts[:default] == ":standard"
    end

    test "refuses a call to the migration's macro in an op" do
      macros = """
      defmacrop same(x), do: quote(do: unquote(x) == @o)
      defmacrop up(x), do: x
      """

      cases = [
        {"default: o()", "", "o/0"},
        {~s|default: "a" \|> up()|, macros, "up/1"},
        {"backfill: fn title -> coalesce(title, ^o()) end", "", "o/0"},
        {~s|default: (case "1" do x when same(x) -> "y"; _x -> "n" end)|, macros, "same/1"},
        # An unquote under options only the compiler can read may run.
        {"default: inspect(quote(@opts, do: unquote(o())))", "", "o/0"},
        # A guard defined where the module body doesn't run vouches for nothing.
        {"default: g(1)", "if false, do: defguardp(g(x) when x == 1)\ndefmacrop g(x), do: x",
         "g/1"},
        # Nor does one beside another clause of its name, or one a macro replaced.
        {"default: g(1)", "defmacrop g(1), do: quote(do: @o)\ndefguardp g(x) when x == 2", "g/1"},
        {"default: g(1)",
         "defguardp g(x) when x == 1\ndefoverridable g: 1\ndefmacrop g(_x), do: quote(do: @o)",
         "g/1"},
        {"default: g(1)",
         "defguardp g(x) when x == 1\nModule.delete_definition(__MODULE__, {:g, 1})\n" <>
           "defmacrop g(_x), do: quote(do: @o)", "g/1"},
        # A head's defaults go only to the clause right after it.
        {"default: g(1)",
         "defguardp g(x, y \\\\ 1)\ndefguardp g(x, y) when x == y\n" <>
           "Module.delete_definition(__MODULE__, {:g, 2})\n" <>
           "Module.delete_definition(__MODULE__, {:g, 1})\n" <>
           "defmacrop g(_x), do: quote(do: @o)\ndefguardp g(x, y) when x == y", "g/1"}
      ]

      for kind <- ["defmacro", "defmacrop"],
          {option, extra, call} <- cases do
        body = """
        @o "1"
        @opts []
        #{kind} o, do: quote(do: @o)

        change_entity MyApp.Task do
          add_attribute :first, :string, #{option}
        end

        #{extra}
        @o "2"
        """

        error =
          assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

        assert error.message ==
                 "a migration op can't call the migration's macro #{call} - make it a defp, or " <>
                   "a defguardp in a guard"

        assert error.line == 8
      end
    end

    test "refuses a guard's shorter arity once a macro replaced its full one" do
      body = """
      @o "1"
      defguardp g(x, y \\\\ "1") when x == y
      defoverridable g: 2
      defmacrop g(_x, _y), do: quote(do: @o)

      change_entity MyApp.Task do
        add_attribute :first, :string, default: if(g("1"), do: "y", else: "n")
      end
      """

      error =
        assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

      assert error.message ==
               "a migration op can't call the migration's macro g/1 - make it a defp, or " <>
                 "a defguardp in a guard"
    end

    test "accepts a guard of the migration and a quoted call to its macro in an op" do
      module =
        compile_migration("20260813091522", """
        @o "1"
        defguardp short(x) when byte_size(x) < 3 and x != @o

        change_entity MyApp.Task do
          add_attribute :first, :string, default: (case "ab" do x when short(x) -> "y"; _x -> "n" end)
          add_attribute :second, :string, default: if(short("1"), do: "y", else: "n")
          add_attribute :third, :string, default: inspect(quote(do: o()))
        end

        defmacrop o, do: quote(do: @o)
        @o "2"
        """)

      assert [
               %{opts: [default: "y"]},
               %{opts: [default: "n"]},
               %{opts: [default: "{:o, [], []}"]}
             ] =
               module.__hologram_migration__().ops
    end

    test "accepts a guard of the migration called with its defaults in an op" do
      # The defaults can be declared in a head of their own.
      for guard <- [
            "defguardp long(text, limit \\\\ 3) when byte_size(text) > limit",
            "defguardp long(text, limit \\\\ 3)\ndefguardp long(text, limit) when byte_size(text) > limit"
          ] do
        module =
          compile_migration("20260813091522", """
          #{guard}

          change_entity MyApp.Task do
            add_attribute :first, :string, default: if(long("Paris"), do: "y", else: "n")
            add_attribute :second, :string, default: if(long("Paris", 9), do: "y", else: "n")
          end
          """)

        assert [%{opts: [default: "y"]}, %{opts: [default: "n"]}] =
                 module.__hologram_migration__().ops
      end
    end

    test "keeps a field access a quote holds as data in an op" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Task do
          add_attribute :first, :string, default: Macro.to_string(quote(do: x.y))
          add_attribute :second, :string, default: Macro.to_string([do: x.y] |> quote())
          add_attribute :third, :string, default: Macro.to_string(quote(do: unquote(%{y: "z"}.y)))
        end
        """)

      assert [
               %{opts: [default: "x.y"]},
               %{opts: [default: "x.y"]},
               %{opts: [default: ~s("z")]}
             ] = module.__hologram_migration__().ops
    end

    test "refuses a field access in an unquote of a quote whose options only the compiler can read" do
      body = """
      @opts []

      change_entity MyApp.Task do
        add_attribute :first, :string,
          default: Macro.to_string(quote(@opts, do: unquote(%{y: "z"}.y)))
      end
      """

      error =
        assert_raise Hologram.CompileError, fn -> compile_migration("20260813091522", body) end

      assert error.message ==
               "a migration can't read a field in an unquote of a quote whose options only the " <>
                 "compiler can read, like an attribute - write the options out, or read the field " <>
                 "with Map.fetch!/2"

      assert error.line == 8
    end

    # Collected from this compile alone, since stderr takes other tests' output too.
    test "raises no unused alias warning for an alias used only in ops" do
      {_module, diagnostics} =
        Code.with_diagnostics(fn ->
          compile_migration("20260813091522", """
          alias MyApp.Task

          create_entity Task
          """)
        end)

      assert Enum.map(diagnostics, & &1.message) == []
    end

    test "names the entity types of its ops as runtime references, not compile-time ones" do
      previous_tracers = Code.get_compiler_option(:tracers)
      Code.put_compiler_option(:tracers, [AliasReferenceTracer | previous_tracers])

      try do
        compile_migration("20260813091522", "create_entity Hologram.MigrationTest.Traced")
      after
        Code.put_compiler_option(:tracers, previous_tracers)
      end

      assert_received {:alias_reference, Hologram.MigrationTest.Traced,
                       {:__hologram_migration__, 0}}

      refute_received {:alias_reference, Hologram.MigrationTest.Traced, nil}
    end
  end

  describe "__using__/1" do
    test "rejects a migration module outside the app/migrations directory" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "lib/my_app/20260813091522.ex uses Hologram.Migration - " <>
          "migration files live in the app/migrations/ directory"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "lib/my_app/20260813091522.ex")
      end
    end

    test "rejects a migration file whose name is not a version" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "invalid migration file name app/migrations/add_tasks.ex - a migration file is named " <>
          "after its version: 14 timestamp digits with the \".ex\" extension, " <>
          "e.g. \"20260813091500.ex\""

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/add_tasks.ex")
      end
    end

    test "rejects a module whose name does not end in the version of its file" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "app/migrations/20260901120000.ex defines MyApp.Migrations.V20260813091522 - " <>
          "the module name must end in V20260901120000"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260901120000.ex")
      end
    end

    test "rejects an op in a module that does not use Hologram.Migration" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration

        defmodule Inner do
          create_entity MyApp.Lost
        end
      end
      """

      expected_msg =
        "migration ops go in the body of a module that uses Hologram.Migration - " <>
          "app/migrations/20260813091522.ex:5"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260813091522.ex")
      end
    end

    test "rejects an op inside a function of a migration module" do
      body = """
      def in_function, do: delete_entity(MyApp.Archive)
      """

      expected_msg =
        "migration ops go in the body of a module that uses Hologram.Migration - " <>
          "app/migrations/20260813091522.ex:4"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    for call <- [
          "add_role(MyApp.Roles.Admin)",
          "change_entity(MyApp.Task, do: add_attribute(:title, :string))",
          "change_role(MyApp.Roles.Admin, extends: MyApp.Roles.Member)",
          "create_entity(MyApp.Task)",
          "create_entity(MyApp.Task, do: add_attribute(:title, :string))",
          "delete_entity(MyApp.Task)",
          "delete_role(MyApp.Roles.Admin)",
          "delete_role_grants()",
          "designate_user_entity(MyApp.User)",
          "rename_entity(MyApp.Old, MyApp.New)",
          "rename_role(MyApp.Roles.Admin, MyApp.Roles.Owner)",
          "resolve!(:attributes)"
        ] do
      test "rejects #{call} inside a function of a migration module" do
        expected_msg =
          "migration ops go in the body of a module that uses Hologram.Migration - " <>
            "app/migrations/20260813091522.ex:4"

        assert_error Hologram.CompileError, expected_msg, fn ->
          compile_migration("20260813091522", "def in_function, do: #{unquote(call)}")
        end
      end
    end

    test "rejects an op in the wrong place before checking its arguments" do
      body = """
      def in_function, do: add_role(:editor)
      """

      expected_msg =
        "migration ops go in the body of a module that uses Hologram.Migration - " <>
          "app/migrations/20260813091522.ex:4"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "rejects an op outside a module" do
      code = """
      import Hologram.Migration

      create_entity MyApp.Task
      """

      expected_msg =
        "migration ops go in the body of a module that uses Hologram.Migration - " <>
          "app/migrations/20260813091522.exs:3"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code, [], file: "app/migrations/20260813091522.exs")
      end
    end

    test "rejects a use outside a module" do
      expected_msg =
        "use Hologram.Migration goes in a migration module - " <>
          "app/migrations/20260813091522.exs:1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("use Hologram.Migration", [], file: "app/migrations/20260813091522.exs")
      end
    end

    test "rejects a migration file in a subdirectory of app/migrations" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "app/migrations/old/20260813091522.ex uses Hologram.Migration - " <>
          "migration files live in the app/migrations/ directory"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/old/20260813091522.ex")
      end
    end

    test "rejects a migration file in a migrations directory outside app" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "lib/migrations/20260813091522.ex uses Hologram.Migration - " <>
          "migration files live in the app/migrations/ directory"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "lib/migrations/20260813091522.ex")
      end
    end

    test "rejects a migration file with the .exs extension" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "invalid migration file name app/migrations/20260813091522.exs - a migration file " <>
          "is named after its version: 14 timestamp digits with the \".ex\" extension, " <>
          "e.g. \"20260813091500.ex\""

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260813091522.exs")
      end
    end

    test "rejects a module named by a bare atom" do
      code = """
      defmodule :scratch_migration do
        use Hologram.Migration
      end
      """

      expected_msg =
        "app/migrations/20260813091522.ex defines :scratch_migration - " <>
          "the module name must end in V20260813091522"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260813091522.ex")
      end
    end
  end

  describe "add_role/2" do
    test "records the op with the role module, an empty opts list by default, and the call line" do
      [result] = ops("add_role MyApp.Roles.Admin")

      assert result == %{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 4}
    end

    test "records the op with the role module, the given opts, and the call line" do
      [result] = ops("add_role MyApp.Roles.Owner, extends: MyApp.Roles.Admin")

      assert result == %{
               op: :add_role,
               role: MyApp.Roles.Owner,
               opts: [extends: MyApp.Roles.Admin],
               line: 4
             }
    end

    test "rejects an atom arg naming an entity role" do
      body = """
      add_role :moderator
      """

      expected_msg =
        "add_role :moderator is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 4)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end

  describe "change_entity/2, backfill" do
    test "an add_attribute op carries a computed backfill as data" do
      assert [op] =
               ops("""
               change_entity MyApp.Task do
                 add_attribute :city, :string, backfill: destination |> split(", ") |> at(0)
               end
               """)

      assert op.opts == [
               backfill: %Value{
                 term: {:at, {:split, {:name, [:destination]}, {:value, ", "}}, {:value, 0}}
               }
             ]
    end

    test "an add_relationship op carries a computed backfill as data" do
      assert [op] =
               ops("""
               change_entity MyApp.Task do
                 add_relationship :owner, MyApp.User, backfill: creator_id
               end
               """)

      assert op.opts == [backfill: %Value{term: {:name, [:creator_id]}}]
    end

    test "a change_attribute op carries a computed backfill as data" do
      assert [op] =
               ops("""
               change_entity MyApp.Task do
                 change_attribute :notes, optional: false, backfill: coalesce(description, "")
               end
               """)

      assert op.changes == [
               optional: false,
               backfill: %Value{
                 term: {:coalesce, [{:name, [:description]}, {:value, ""}]}
               }
             ]
    end

    test "a change_relationship op carries a computed backfill as data" do
      assert [op] =
               ops("""
               change_entity MyApp.Task do
                 change_relationship :owner, optional: false, backfill: trip.owner_id
               end
               """)

      assert op.changes == [
               optional: false,
               backfill: %Value{term: {:name, [:trip, :owner_id]}}
             ]
    end

    test "a pinned attribute inside an expression reads its value at the op's line" do
      assert [first, second] =
               ops("""
               @fallback "first"

               change_entity MyApp.Task do
                 add_attribute :a, :string, backfill: coalesce(title, ^@fallback)
               end

               @fallback "second"

               change_entity MyApp.Task do
                 add_attribute :b, :string, backfill: coalesce(title, ^@fallback)
               end
               """)

      assert first.opts[:backfill].term == {:coalesce, [{:name, [:title]}, {:value, "first"}]}
      assert second.opts[:backfill].term == {:coalesce, [{:name, [:title]}, {:value, "second"}]}
    end

    test "a pinned call to the migration's own function reads its result" do
      assert [op] =
               ops("""
               change_entity MyApp.Task do
                 add_attribute :tier, :string, backfill: ^default_tier()
               end

               def default_tier, do: "standard"
               """)

      assert op.opts == [backfill: "standard"]
    end

    test "options from a call pass through unlowered" do
      assert [op] =
               ops("""
               change_entity MyApp.Task do
                 add_attribute :tier, :string, tier_opts()
               end

               def tier_opts, do: [backfill: "standard"]
               """)

      assert op.opts == [backfill: "standard"]
    end

    test "refuses at the line of the op" do
      error =
        assert_raise Hologram.CompileError, fn ->
          ops("""
          change_entity MyApp.Task do
            add_attribute :a, :string

            add_attribute :b, :string, backfill: at(split(title, ""), 0)
          end
          """)
        end

      assert error.line == 7
    end
  end

  describe "change_entity/2" do
    test "records the member ops with the entity type injected" do
      result =
        ops("""
        change_entity MyApp.Task do
          add_attribute(:priority, :integer, backfill: 0)
          change_attribute(:estimate, type: :float)
          delete_attribute(:legacy)
          rename_attribute(:name, :title)
          resolve!(:attributes, deleted: [:name])
        end
        """)

      assert [add_op, change_op, delete_op, rename_op, resolve_op] = result

      assert add_op == %{
               op: :add_attribute,
               entity: MyApp.Task,
               name: :priority,
               type: :integer,
               opts: [backfill: 0],
               line: 5
             }

      assert change_op == %{
               op: :change_attribute,
               entity: MyApp.Task,
               name: :estimate,
               changes: [type: :float],
               line: 6
             }

      assert delete_op == %{
               op: :delete_attribute,
               entity: MyApp.Task,
               name: :legacy,
               line: 7
             }

      assert rename_op == %{
               op: :rename_attribute,
               entity: MyApp.Task,
               from: :name,
               to: :title,
               line: 8
             }

      assert resolve_op == %{
               op: :resolve!,
               entity: MyApp.Task,
               kind: :attributes,
               payload: [deleted: [:name]],
               line: 9
             }
    end

    test "records enum value member ops with the entity type injected" do
      result =
        ops("""
        change_entity MyApp.Task do
          add_enum_value(:status, :archived, after: :done)
          delete_enum_value(:status, :draft)
          rename_enum_value(:status, :done, :completed)
          reorder_enum_values(:status, [:todo, :doing, :completed])
        end
        """)

      assert [add_op, delete_op, rename_op, reorder_op] = result

      assert add_op == %{
               op: :add_enum_value,
               entity: MyApp.Task,
               attribute: :status,
               value: :archived,
               opts: [after: :done],
               line: 5
             }

      assert delete_op == %{
               op: :delete_enum_value,
               entity: MyApp.Task,
               attribute: :status,
               value: :draft,
               line: 6
             }

      assert rename_op == %{
               op: :rename_enum_value,
               entity: MyApp.Task,
               attribute: :status,
               from: :done,
               to: :completed,
               line: 7
             }

      assert reorder_op == %{
               op: :reorder_enum_values,
               entity: MyApp.Task,
               attribute: :status,
               values: [:todo, :doing, :completed],
               line: 8
             }
    end

    test "records relationship member ops with the entity type injected" do
      result =
        ops("""
        change_entity MyApp.Task do
          add_relationship(:author, MyApp.User)
          add_relationship(:tags, [MyApp.Tag], optional: true)
          change_relationship(:author, optional: true)
          delete_relationship(:legacy_project)
          rename_relationship(:author, :creator)
        end
        """)

      assert [add_one_op, add_many_op, change_op, delete_op, rename_op] = result

      assert add_one_op == %{
               op: :add_relationship,
               entity: MyApp.Task,
               name: :author,
               type: MyApp.User,
               opts: [],
               line: 5
             }

      assert add_many_op == %{
               op: :add_relationship,
               entity: MyApp.Task,
               name: :tags,
               type: [MyApp.Tag],
               opts: [optional: true],
               line: 6
             }

      assert change_op == %{
               op: :change_relationship,
               entity: MyApp.Task,
               name: :author,
               changes: [optional: true],
               line: 7
             }

      assert delete_op == %{
               op: :delete_relationship,
               entity: MyApp.Task,
               name: :legacy_project,
               line: 8
             }

      assert rename_op == %{
               op: :rename_relationship,
               entity: MyApp.Task,
               from: :author,
               to: :creator,
               line: 9
             }
    end

    test "records role member ops with the entity type injected" do
      result =
        ops("""
        change_entity MyApp.Task do
          add_role(:editor)
          add_role(:owner, extends: :editor)
          change_role(:owner, granted_to: :creator)
          delete_role(:viewer)
          rename_role(:moderator, :maintainer)
        end
        """)

      assert [add_op, add_extends_op, change_op, delete_op, rename_op] = result

      assert add_op == %{
               op: :add_role,
               entity: MyApp.Task,
               name: :editor,
               opts: [],
               line: 5
             }

      assert add_extends_op == %{
               op: :add_role,
               entity: MyApp.Task,
               name: :owner,
               opts: [extends: :editor],
               line: 6
             }

      assert change_op == %{
               op: :change_role,
               entity: MyApp.Task,
               name: :owner,
               changes: [granted_to: :creator],
               line: 7
             }

      assert delete_op == %{
               op: :delete_role,
               entity: MyApp.Task,
               name: :viewer,
               line: 8
             }

      assert rename_op == %{
               op: :rename_role,
               entity: MyApp.Task,
               from: :moderator,
               to: :maintainer,
               line: 9
             }
    end

    test "records key member ops with the entity type injected" do
      result =
        ops("""
        change_entity MyApp.Task do
          add_unique([:workspace, :slug])
          delete_unique([:kind, :slug])
        end
        """)

      assert result == [
               %{op: :add_unique, entity: MyApp.Task, fields: [:workspace, :slug], line: 5},
               %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug], line: 6}
             ]
    end

    test "records a one-op list for a single-statement block" do
      result =
        ops("""
        change_entity MyApp.Task do
          add_attribute(:body, :string)
        end
        """)

      assert [add_op] = result

      assert add_op == %{
               op: :add_attribute,
               entity: MyApp.Task,
               name: :body,
               type: :string,
               opts: [],
               line: 5
             }
    end

    test "rejects an unknown op naming it with its line" do
      body = """
      change_entity MyApp.Task do
        add_column :title, :string
      end
      """

      expected_msg =
        "unknown migration op add_column/2 at line 5 - see Hologram.Migration for the vocabulary"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "rejects a statement that is not an op call" do
      body = """
      change_entity MyApp.Task do
        42
      end
      """

      expected_msg =
        "invalid statement in a migration entity block starting at line 4 - " <>
          "entity blocks contain only member ops"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "rejects a role op with a module arg inside the block" do
      body = """
      change_entity MyApp.Task do
        rename_role MyApp.Roles.Admin, MyApp.Roles.Owner
      end
      """

      expected_msg =
        "rename_role with a role module is a flat top-level statement - " <>
          "move it out of the entity block (line 5)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end

  describe "change_role/2" do
    test "records the op with the role module, the changes, and the call line" do
      [result] = ops("change_role MyApp.Roles.Owner, extends: MyApp.Roles.Admin")

      assert result == %{
               op: :change_role,
               role: MyApp.Roles.Owner,
               changes: [extends: MyApp.Roles.Admin],
               line: 4
             }
    end

    test "rejects an atom arg naming an entity role" do
      body = """
      change_role :owner, granted_to: :creator
      """

      expected_msg =
        "change_role :owner is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 4)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end

  describe "locals_without_parens/0" do
    test "is exported by the framework formatter config" do
      {config, _binding} = Code.eval_file(".formatter.exs")
      exported = get_in(config, [:export, :locals_without_parens])

      assert locals_without_parens() -- exported == []
    end
  end

  describe "create_entity/1" do
    test "records the op with the entity type and the call line" do
      [result] = ops("create_entity MyApp.Task")

      assert result == %{op: :create_entity, entity: MyApp.Task, line: 4}
    end
  end

  describe "create_entity/2" do
    test "records the creation op followed by the member ops" do
      result =
        ops("""
        create_entity MyApp.Comment do
          add_attribute(:body, :string)
        end
        """)

      assert [create_op, add_op] = result
      assert create_op == %{op: :create_entity, entity: MyApp.Comment, line: 4}

      assert add_op == %{
               op: :add_attribute,
               entity: MyApp.Comment,
               name: :body,
               type: :string,
               opts: [],
               line: 5
             }
    end

    test "records only the creation op for an empty block" do
      result =
        ops("""
        create_entity MyApp.Marker do
        end
        """)

      assert [create_op] = result
      assert create_op == %{op: :create_entity, entity: MyApp.Marker, line: 4}
    end
  end

  describe "delete_entity/1" do
    test "records the op with the entity type and the call line" do
      [result] = ops("delete_entity MyApp.Task")

      assert result == %{op: :delete_entity, entity: MyApp.Task, line: 4}
    end
  end

  describe "delete_role/1" do
    test "records the op with the role module and the call line" do
      [result] = ops("delete_role MyApp.Roles.Admin")

      assert result == %{op: :delete_role, role: MyApp.Roles.Admin, line: 4}
    end

    test "rejects an atom arg naming an entity role" do
      body = """
      delete_role :moderator
      """

      expected_msg =
        "delete_role :moderator is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 4)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end

  describe "rename_entity/2" do
    test "records the op with both entity type names and the call line" do
      [result] = ops("rename_entity MyApp.Draft, MyApp.Sketch")

      assert result == %{
               op: :rename_entity,
               from: MyApp.Draft,
               to: MyApp.Sketch,
               line: 4
             }
    end
  end

  describe "rename_role/2" do
    test "records the op with both role modules and the call line" do
      [result] = ops("rename_role MyApp.Roles.Admin, MyApp.Roles.Owner")

      assert result == %{
               op: :rename_role,
               from: MyApp.Roles.Admin,
               to: MyApp.Roles.Owner,
               line: 4
             }
    end

    test "rejects an atom arg naming an entity role" do
      body = """
      rename_role :moderator, :maintainer
      """

      expected_msg =
        "rename_role :moderator is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 4)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end

  describe "resolve!/2" do
    test "records the op with the kind, an empty payload by default, and the call line" do
      [result] = ops("resolve! :attributes")

      assert result == %{op: :resolve!, kind: :attributes, payload: [], line: 4}
    end

    test "records the op with the kind, the given payload, and the call line" do
      [result] = ops("resolve! :attributes, deleted: [:name], added: [:title]")

      assert result == %{
               op: :resolve!,
               kind: :attributes,
               payload: [deleted: [:name], added: [:title]],
               line: 4
             }
    end
  end
end
