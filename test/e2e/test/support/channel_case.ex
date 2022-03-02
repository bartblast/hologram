defmodule HologramE2E.Test.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import HologramE2E.Test.ChannelCase
      import HologramE2E.Test.Helpers

      @endpoint HologramE2EWeb.Endpoint
      @fixtures_path "test/fixtures"
    end
  end
end
