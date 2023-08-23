# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.Component.Module2 do
  use Hologram.Component

  def init(_props, client) do
    put_state(client, :overriden, true)
  end

  def init(_props, client, server) do
    {put_state(client, :overriden, true), server}
  end

  def template do
    ~H"""
    Module2 template
    """
  end
end
