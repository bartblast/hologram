defmodule HologramClusterTests.TestCase do
  use ExUnit.CaseTemplate

  # Based on Wallaby.Feature.__using__/1
  using do
    quote do
      ExUnit.Case.register_attribute(__MODULE__, :sessions)

      # Kernel.tap/2 conflicts with Browser.tap/2
      import Kernel, except: [tap: 2]

      import HologramClusterTests.Cluster
      import Wallaby.Browser
      import Wallaby.Feature
      import Wallaby.Query

      alias HologramClusterTests.Proxy

      setup context do
        Hologram.Test.FeatureHelpers.start_sessions(context)
      end
    end
  end
end
