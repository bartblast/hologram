defmodule Hologram.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import Hologram.ChannelCase
      import Hologram.Test.Helpers

      @endpoint Hologram.E2E.Web.Endpoint
    end
  end
end
