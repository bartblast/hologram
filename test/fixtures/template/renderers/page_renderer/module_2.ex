defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module2 do
  use Hologram.Layout

  def init do
    %{
      b: 987
    }
  end

  def template do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <Hologram.UI.Runtime />
      </head>
      <body>
        layout template {@b}
        <slot />
      </body>
    </html>
    """
  end
end
