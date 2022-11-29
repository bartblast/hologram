defmodule HologramE2E.TestCase do
  use ExUnit.CaseTemplate
  alias Hologram.Runtime.{PageDigestStore, RouterBuilder, RouterMatcher}

  using do
    quote do
      use HologramE2E.OverridenWallabyFeature

      import HologramE2E.Test.Helpers
      import Wallaby.Query

      @fixtures_path "#{File.cwd!()}/test/fixtures"

      setup_all do
        Mix.Tasks.Compile.Hologram.run()

        PageDigestStore.populate_table()

        :code.delete(RouterMatcher)
        RouterBuilder.create_matcher_module()

        :ok
      end
    end
  end
end
