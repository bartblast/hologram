defmodule Hologram.E2ECase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature
      
      import Hologram.Test.Helpers
      import Wallaby.Query
    end
  end
end
