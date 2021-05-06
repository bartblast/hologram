defmodule Hologram.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Hologram.Test.Helpers
    end
  end
end
