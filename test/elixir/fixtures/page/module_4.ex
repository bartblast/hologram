defmodule Hologram.Test.Fixtures.Page.Module4 do
  use Hologram.Layout

  @impl Layout
  def template do
    ~H"""
    Module4 template
    """
  end
end
