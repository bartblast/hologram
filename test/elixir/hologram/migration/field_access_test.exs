defmodule Hologram.Migration.FieldAccessTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.FieldAccess

  defp rewritten(code) do
    code
    |> Code.string_to_quoted!()
    |> rewrite()
    |> Macro.to_string()
  end

  defp unchanged?(code) do
    ast = Code.string_to_quoted!(code)
    rewrite(ast) == ast
  end

  describe "rewrite/1" do
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

    test "leaves a field of an unquote fragment's value to be decided once it is unquoted" do
      assert rewritten("unquote(value).name") ==
               "Hologram.Migration.FieldAccess.Definitions.__field__(unquote(value), :name)"
    end

    test "rewrites a field named by an unquote fragment and keeps a call it names" do
      assert rewritten("row.unquote(name)") == ":erlang.map_get(unquote(name), row)"
      assert unchanged?("row.unquote(name)()")
    end
  end
end
