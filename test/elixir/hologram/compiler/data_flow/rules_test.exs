defmodule Hologram.Compiler.DataFlow.RulesTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Rules

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module25
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Rules1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Rules2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Rules3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  defp flow(rules), do: DataFlow.start(PLT.start(), PLT.start(), rules: rules)

  describe "built_in/0" do
    test "lists the Ash rules, then the Ecto rules, which Ash is built on" do
      assert built_in() == [
               Hologram.Compiler.DataFlow.Rules.Ash,
               Hologram.Compiler.DataFlow.Rules.Ecto
             ]
    end
  end

  describe "record/2" do
    test "the first rules module's record wins" do
      assert record(Struct1, flow([Rules2, Rules3])) == [{:struct, Struct1, %{}}]
      assert record(Struct1, flow([Rules3, Rules2])) == [{:struct, Struct1, %{field: [:prim]}}]
    end

    test "a rules module without the callback, or answering nil, is skipped" do
      assert record(Struct2, flow([Rules1, Rules2, Rules3])) == [{:struct, Struct2, %{}}]
    end

    test "nil when no rules module knows the module's records" do
      assert record(Module25, flow([Rules1, Rules2, Rules3])) == nil
    end

    test "nil without rules modules" do
      assert record(Struct1, flow([])) == nil
    end
  end

  describe "summary/2" do
    test "the first rules module's answer wins" do
      assert summary({Module25, :ruled, 0}, flow([Rules1, Rules2])) ==
               [{:struct, Struct1, %{field: [:prim]}}]

      assert summary({Module25, :ruled, 0}, flow([Rules2, Rules1])) == [:prim]
    end

    test "nil when no rules module answers" do
      assert summary({Module25, :calls_ruled, 0}, flow([Rules1, Rules2])) == nil
    end

    test "nil without rules modules" do
      assert summary({Module25, :ruled, 0}, flow([])) == nil
    end
  end
end
