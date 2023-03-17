defmodule Hologram.Compiler.ASTTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Compiler.AST

  test "for_code/1" do
    assert AST.for_code("1 + 2") == {:+, [line: 1], [1, 2]}
  end
end
