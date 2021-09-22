defmodule Hologram.Test.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import Hologram.Test.ChannelCase
      import Hologram.Test.Helpers

      @endpoint Hologram.E2E.Web.Endpoint
    end
  end
end
