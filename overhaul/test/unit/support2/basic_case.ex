defmodule Hologram.Test.BasicCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Hologram.Test.Helpers

      @fixtures_path "#{File.cwd!()}/test/elixir/fixtures"
    end
  end
end
