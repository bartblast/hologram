defmodule App1.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      import Hologram.Test.FeatureHelpers
      import Wallaby.Browser, except: [visit: 2]
      import Wallaby.Query
    end
  end
end
