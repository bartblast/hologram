defmodule HologramE2E.TestCase do
  use ExUnit.CaseTemplate
  alias Hologram.Runtime.{PageDigestStore, RouterBuilder, RouterMatcher, TemplateStore}

  using do
    quote do
      use Wallaby.Feature
      import Wallaby.Query

      @fixtures_path "test/fixtures"

      setup_all do
        Mix.Tasks.Compile.Hologram.run()

        PageDigestStore.populate_table()
        TemplateStore.populate_table()

        :code.delete(RouterMatcher)
        RouterBuilder.create_matcher_module()

        :ok
      end
    end
  end
end
