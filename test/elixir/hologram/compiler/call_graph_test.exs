defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph
  alias Hologram.Compiler.CallGraph

  @name :"cg_#{__MODULE__}"
  @opts name: @name

  setup do
    [call_graph: start(@opts)]
  end

  test "data/1", %{call_graph: call_graph} do
    assert %Graph{} = CallGraph.data(call_graph)
  end

  describe "start/1" do
    test "%CallGraph{} struct is returned" do
      assert %CallGraph{name: @name} = start(name: @name <> "_start_test")
    end

    test "process name is registered" do
      %CallGraph{pid: pid} = start(name: @name <> "_start_test")
      assert Process.whereis(@name) == pid
    end
  end
end
