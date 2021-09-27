defmodule Hologram.Test.UnitCase  do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Hologram.Test.Helpers
      import Hologram.Compiler.Helpers, only: [ast: 1, ir: 1]
    end
  end
end
