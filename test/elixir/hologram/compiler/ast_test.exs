defmodule Hologram.Compiler.ASTTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.AST

  test "for_code/1" do
    assert for_code("1 + 2") == {:+, [line: 1], [1, 2]}
  end
end
