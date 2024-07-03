defmodule Hologram.Compiler.ASTTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.AST
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module1

  test "for_code/1" do
    assert for_code("1 + 2") == {:+, [line: 1], [1, 2]}
  end

  describe "for_module/2" do
    @expected {:defmodule, [context: Elixir, import: Kernel],
               [
                 {:__aliases__, [alias: false],
                  [:Hologram, :Test, :Fixtures, :Compiler, :Tranformer, :Module1]},
                 [
                   do:
                     {:__block__, [],
                      [
                        {:def, [line: 3],
                         [
                           {:my_fun, [],
                            [{:x, [version: 0, line: 3], nil}, {:y, [version: 1, line: 3], nil}]},
                           [
                             do:
                               {:__block__, [],
                                [
                                  {{:., [line: 4], [:erlang, :+]}, [line: 4],
                                   [
                                     {:x, [version: 0, line: 4], nil},
                                     {:y, [version: 1, line: 4], nil}
                                   ]}
                                ]}
                           ]
                         ]}
                      ]}
                 ]
               ]}

    test "with BEAM path not specified" do
      assert for_module(Module1) == @expected
    end

    test "with BEAM path specified" do
      beam_path = :code.which(Module1)
      assert for_module(Module1, beam_path) == @expected
    end
  end
end
