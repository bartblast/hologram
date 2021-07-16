defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module8 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module9

  def action(:test_1, _a, _b) do
    Module9.some_fun()
  end
end
