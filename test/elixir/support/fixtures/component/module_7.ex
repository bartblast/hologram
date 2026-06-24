defmodule Hologram.Test.Fixtures.Component.Module7 do
  use Hologram.Component

  @impl Component
  def middleware(server) do
    put_status(server, :forbidden)
  end

  @impl Component
  def template do
    ~HOLO"""
    Module7 template
    """
  end
end
