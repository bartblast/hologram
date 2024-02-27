# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.Component.Module2 do
  use Hologram.Component

  def init(_props, component) do
    put_state(component, :overriden, true)
  end

  def init(_props, component, server) do
    {put_state(component, :overriden, true), server}
  end

  def template do
    ~H"""
    Module2 template
    """
  end
end
