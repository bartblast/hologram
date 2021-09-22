defmodule Hologram.UI.Runtime do
  use Hologram.Component

  def template do
    ~H"""
    <script src="/hologram/hologram.js"></script>
    <script src="{@context.__src__}"></script>
    <script>
      Hologram.run(window, {@context.__class__}, "{@context.__state__}")
    </script>
    """
  end
end
