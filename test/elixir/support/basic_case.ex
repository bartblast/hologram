defmodule Hologram.Test.BasicCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Hologram.Commons.TestUtils
      import Hologram.Test.Helpers

      @fixtures_dir "#{File.cwd!()}/test/elixir/support/fixtures"
    end
  end
end
