defmodule Hologram.Test.E2ECase do
  use ExUnit.CaseTemplate
  alias Hologram.Runtime.{PageDigestStore, RouterBuilder, RouterMatcher, TemplateStore}

  using do
    quote do
      use Wallaby.Feature

      import Hologram.Test.Helpers
      import Wallaby.Query

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
