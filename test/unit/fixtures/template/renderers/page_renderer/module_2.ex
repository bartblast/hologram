defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module2 do
  use Hologram.Layout

  def init(conn) do
    %{
      b: 987,
      e: conn.session.e
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
        layout template assign {@b}, layout template conn session {@e}
        <slot />
      </body>
    </html>
    """
  end
end
