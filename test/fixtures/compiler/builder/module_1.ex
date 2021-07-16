defmodule Hologram.Test.Fixtures.Compiler.Builder.Module1 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.Builder.Module2
  alias Hologram.Test.Fixtures.Compiler.Builder.Module3

  def action(:test, _a, _b) do
    Module3.test_3()
  end

  # prevent unused alias compiler warning
  Module2
end
