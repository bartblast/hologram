defmodule Hologram.Test.UnitCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Hologram.Compiler.Reflection, only: [ast: 1, ir: 1]
      import Hologram.Test.Helpers

      alias Hologram.Utils
    end
  end
end
