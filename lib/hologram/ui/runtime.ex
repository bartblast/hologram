defmodule Hologram.UI.Runtime do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <script src="/hologram/runtime.js"></script>
    <script src="{@context.__src__}"></script>
    <script>
      Hologram.run({@context.__class__}, "{@context.__state__}")
    </script>
    """
  end
end
