defmodule Hologram.Compiler.ASTTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.AST
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module1

  test "for_code/1" do
    assert for_code("1 + 2") == {:+, [line: 1], [1, 2]}
  end

  describe "for_module/2" do
    test "with BEAM path not specified" do
      assert {:defmodule, [context: Elixir, import: Kernel],
              [
                {:__aliases__, [alias: false],
                 [:Hologram, :Test, :Fixtures, :Compiler, :Tranformer, :Module1]},
                _body
              ]} = for_module(Module1)
    end

    test "with BEAM path specified" do
      beam_path = :code.which(Module1)

      assert {:defmodule, [context: Elixir, import: Kernel],
              [
                {:__aliases__, [alias: false],
                 [:Hologram, :Test, :Fixtures, :Compiler, :Tranformer, :Module1]},
                _body
              ]} = for_module(Module1, beam_path)
    end
  end
end
