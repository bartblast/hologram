# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.Layout.Module2 do
  use Hologram.Layout

  def init(_props, client, server) do
    {put_state(client, :overriden, true), server}
  end

  def template do
    ~H"""
    Module2 template
    """
  end
end
