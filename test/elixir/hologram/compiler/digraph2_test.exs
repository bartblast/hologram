defmodule Hologram.Compiler.Digraph2Test do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Digraph2
  alias Hologram.Compiler.Digraph2

  describe "new/0" do
    test "creates a new digraph" do
      assert new() == %Digraph2{vertices: %{}, edges: %{}, reverse_edges: %{}}
    end
  end
end
