defmodule Hologram.Compiler.ImportTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.ImportTransformer
  alias Hologram.Compiler.IR.Import

  test "transform/2" do
    module_segs = [:Hologram, :Compiler, :ImportTransformerTest]
    only = [abc: 2]

    result = ImportTransformer.transform(module_segs, only)
    expected_module = Hologram.Compiler.ImportTransformerTest
    expected = %Import{module: expected_module, only: only}

    assert result == expected
  end
end
