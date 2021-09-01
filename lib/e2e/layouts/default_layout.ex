defmodule Hologram.E2E.DefaultLayout do
  use Hologram.Layout

  def template do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <script src="/js/hologram.js"></script>
        <script src="{@context.__src__}"></script>
        <script>
          Hologram.run(window, {@context.__class__}, "{@context.__state__}")
        </script>
      </head>
      <body>
        default layout:
        <slot />
      </body>
    </html>
    """
  end
end
