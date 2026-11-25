defmodule Hologram.Migration.FieldAccessTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.FieldAccess

  # ExUnit can start a test while its module is still closing, which the lookup of the
  # migration's own macros can't read.
  defp env, do: %{__ENV__ | module: nil, function: nil}

  defp rewritten(code) do
    code
    |> Code.string_to_quoted!()
    |> rewrite(env())
    |> Macro.to_string()
  end

  defp unchanged?(code) do
    ast = Code.string_to_quoted!(code)
    rewrite(ast, env()) == ast
  end

  describe "define/4" do
    test "refuses a function or macro whose body is an empty list" do
      for kind <- [:def, :defmacro] do
        assert_raise Hologram.CompileError, ~r/take their body as do: or a do block/, fn ->
          define(kind, env(), quote(do: m), [])
        end
      end
    end

    test "refuses an unquoted body that isn't a keyword list where the definition runs" do
      for kind <- [:def, :defmacro] do
        assert_raise Hologram.CompileError, ~r/take their body as do: or a do block/, fn ->
          compile_migration("20260813091522", "#{kind} m, unquote(:body)")
        end
      end
    end

    test "leaves a function's body to be rewritten where Elixir expands it" do
      definition = define(:def, env(), quote(do: f(row)), do: quote(do: row.name))

      assert Macro.to_string(definition) ==
               "Kernel.def f(row) do\n  Definitions.__body__(row.name)\nend"
    end
  end

  describe "rewrite/3" do
    test "rewrites a field access on a variable into a strict map read" do
      assert rewritten("row.name") == ":erlang.map_get(:name, row)"
    end

    test "rewrites nested field access from the inside out" do
      assert rewritten("row.a.b") == ":erlang.map_get(:b, :erlang.map_get(:a, row))"
    end

    test "rewrites a field access on an attribute and on a placeholder" do
      assert rewritten("@config.name") == ":erlang.map_get(:name, @config)"
      assert rewritten("& &1.id") == "&:erlang.map_get(:id, &1)"
    end

    test "keeps a remote call without parentheses on a module name" do
      assert unchanged?("MyApp.Task.name")
      assert unchanged?(":math.pi")
      assert unchanged?("__MODULE__.name")
    end

    test "keeps a call with parentheses" do
      assert unchanged?("row.name()")
    end

    test "keeps a capture of a function and rewrites a capture dividing a field" do
      assert unchanged?("&mod.fun/1")
      assert rewritten("&(&1.total / 2)") == "&(:erlang.map_get(:total, &1) / 2)"
    end

    test "keeps the path of a path macro and rewrites the keys in its brackets" do
      assert rewritten("put_in(row.items[item.id], 1)") ==
               "put_in(row.items[:erlang.map_get(:id, item)], 1)"

      assert unchanged?("Kernel.update_in(row.a, f)")
      assert unchanged?("Elixir.Kernel.update_in(row.a, f)")
      assert unchanged?("get_in(row.a.b)")
    end

    test "rewrites the value given to a path function" do
      assert rewritten("get_in(row.data, [:a])") == "get_in(:erlang.map_get(:data, row), [:a])"
    end

    test "keeps the piped path of a path macro and rewrites what a path function is piped" do
      assert rewritten("row.a.b |> put_in(1)") == "row.a.b |> put_in(1)"

      assert rewritten("row.data |> put_in(row.path, 1)") ==
               ":erlang.map_get(:data, row) |> put_in(:erlang.map_get(:path, row), 1)"

      assert rewritten("row.a.b |> Kernel.put_in(1)") == "row.a.b |> Kernel.put_in(1)"
      assert unchanged?("row.a.b |> Elixir.Kernel.put_in(1)")
    end

    test "takes an alias of Kernel as Kernel, expanding only a module name" do
      aliased = %{env() | aliases: [{K, Kernel}]}
      ast = Code.string_to_quoted!("K.|>(row.a.b, put_in(1))")

      assert rewrite(ast, aliased) == ast

      for code <- ["row.a.b |> K.put_in(1)", "K.get_in(row.a.b)"] do
        ast = Code.string_to_quoted!(code)

        assert rewrite(ast, aliased) == ast
      end

      assert rewritten("K.get_in(row.a.b)") ==
               "K.get_in(:erlang.map_get(:b, :erlang.map_get(:a, row)))"

      assert rewritten("(1 |> 2).|>(row.a, f())") ==
               "(1 |> 2).|>(:erlang.map_get(:a, row), f())"
    end

    test "leaves a field of an unquote fragment's value to be decided once it is unquoted" do
      assert rewritten("unquote(value).name") ==
               "Hologram.Migration.FieldAccess.Definitions.__field__(unquote(value), :name)"
    end

    test "keeps a quote's code as data and rewrites the code it runs" do
      assert unchanged?("quote(do: x.y)")
      assert unchanged?("[do: x.y] |> quote()")
      assert unchanged?("quote(@opts, do: unquote(x))")

      assert rewritten("quote(do: unquote(x.y))") ==
               "quote do\n  unquote(:erlang.map_get(:y, x))\nend"

      assert rewritten("quote(bind_quoted: [v: x.y], do: v.z)") ==
               "quote bind_quoted: [v: :erlang.map_get(:y, x)], do: v.z"

      assert unchanged?("Kernel.|>([do: x.y], quote())")
      assert unchanged?("quote(unquote: false, do: unquote(x.y))")
      assert unchanged?("quote(do: quote(do: unquote(unquote(x.y))))")
    end

    test "refuses a field access an unquote runs in a quote whose options only the compiler can read" do
      assert_raise Hologram.CompileError, ~r/read a field in an unquote of a quote/, fn ->
        rewritten("quote(@opts, do: unquote(x.y))")
      end
    end

    test "rewrites a field named by an unquote fragment and keeps a call it names" do
      assert rewritten("row.unquote(name)") == ":erlang.map_get(unquote(name), row)"
      assert unchanged?("row.unquote(name)()")
    end
  end
end
