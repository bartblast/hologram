defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module21 do
  use Hologram.Page

  def action(:test_1, _a, _b) do
    to_string(123)
  end
end
