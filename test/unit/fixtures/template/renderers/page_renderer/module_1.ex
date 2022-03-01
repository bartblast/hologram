defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module1 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Template.PageRenderer.Module2

  route "/test-route-1"

  def init do
    %{
      a: 123
    }
  end

  def template do
    ~H"""
    page template {@a}
    """
  end
end
