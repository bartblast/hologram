# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Layout.Module2 do
  use Hologram.Layout

  def init(_props, component, server) do
    {put_state(component, :overriden, true), server}
  end

  def template do
    ~H"""
    Module2 template
    """
  end
end
