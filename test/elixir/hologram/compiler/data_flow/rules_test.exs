defmodule Hologram.Compiler.DataFlow.RulesTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Rules

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module25
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Rules1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Rules2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  defp flow(rules), do: DataFlow.start(PLT.start(), PLT.start(), rules: rules)

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
