defmodule Hologram.Test.E2ECase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      import Hologram.Test.Helpers
      import Wallaby.Query

      setup_all do
        Mix.Tasks.Compile.Hologram.run()
        :ok
      end
    end
  end
end
