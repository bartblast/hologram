defmodule Hologram.Test.ComponentCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Hologram.Template, only: [sigil_H: 2]
      import Hologram.Test.Helpers

      @fixtures_dir "#{File.cwd!()}/test/elixir/support/fixtures"
    end
  end
end
