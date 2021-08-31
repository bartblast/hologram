defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module1 do
  use Hologram.Page

  def state do
    %{
      a: 123
    }
  end

  def template do
    ~H"""
    <div>test template {@a}</div>
    """
  end
end
