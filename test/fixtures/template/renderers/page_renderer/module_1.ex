defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module1 do
  use Hologram.Component

  def state do
    %{
      a: 123
    }
  end

  def template do
    ~H"""
    <body>
      <div>test template {@a}</div>
    </body>
    """
  end
end
