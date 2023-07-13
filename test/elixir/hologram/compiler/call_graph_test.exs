defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph
  alias Hologram.Compiler.CallGraph

  @name :"cg_#{__MODULE__}"
  @opts name: @name

  test "data/1" do
    cg = start(@opts)
    assert %Graph{} = CallGraph.data(cg)
  end

  describe "start/1" do
    test "%CallGraph{} struct is returned" do
      assert %CallGraph{name: @name} = start(@opts)
    end

    test "process name is registered" do
      %CallGraph{pid: pid} = start(@opts)
      assert Process.whereis(@name) == pid
    end
  end
end
