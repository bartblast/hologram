defmodule Hologram.E2E.Web.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import Hologram.E2E.Web.ChannelCase

      @endpoint Hologram.E2E.Web.Endpoint
    end
  end
end
