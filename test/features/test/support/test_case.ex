defmodule HologramFeatureTests.TestCase do
  use ExUnit.CaseTemplate

  # Based on Wallaby.Feature.__using__/1
  using do
    quote do
      ExUnit.Case.register_attribute(__MODULE__, :sessions)

      # Hologram.Commons.KernelUtils.inspect/1 is used instead of Kernel.inspect/1
      # Kernel.tap/2 was introduced in 1.12 and conflicts with Browser.tap/2
      import Kernel, except: [inspect: 1, tap: 2]

      import Hologram.Commons.KernelUtils, only: [inspect: 1]
      import Hologram.Commons.TestUtils
      import Hologram.Test.FeatureHelpers
      import HologramFeatureTests.Helpers

      import Wallaby.Browser,
        except: [
          assert_text: 2,
          assert_text: 3,
          cookies: 1,
          has_text?: 2,
          refute_has: 2,
          send_keys: 2,
          visit: 2
        ]

      import Wallaby.Feature
      import Wallaby.Query

      setup context do
        Hologram.Test.FeatureHelpers.start_sessions(context)
      end
    end
  end
end
