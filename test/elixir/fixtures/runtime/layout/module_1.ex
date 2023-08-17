defmodule Hologram.Test.Fixtures.Runtime.Layout.Module1 do
  use Hologram.Layout

  @impl Layout
  def template do
    ~H"""
    Module1 template
    """
  end
end
