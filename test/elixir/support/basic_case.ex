defmodule Hologram.Test.BasicCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @fixtures_path "#{File.cwd!()}/test/elixir/fixtures"
    end
  end
end
