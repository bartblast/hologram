defmodule Hologram.Test.UnitCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Hologram.Test.Helpers
      import Hologram.Compiler.Helpers, only: [ir: 1]
      import Hologram.Compiler.Reflection, only: [ast: 1]
    end
  end
end
