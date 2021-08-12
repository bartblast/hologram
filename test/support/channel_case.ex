defmodule Hologram.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import Hologram.ChannelCase
      import Hologram.Test.Helpers

      alias Hologram.Runtime.Channel
      alias Hologram.Runtime.Socket

      @endpoint DemoWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Demo.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Demo.Repo, {:shared, self()})
    end

    :ok
  end
end
