defmodule Hologram.UI.Runtime do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <script src="/hologram/manifest.js"></script>
    <script src={static_path("/hologram/runtime.js")} hologram-policy="no-reload"></script>
    <script src="/hologram/page-{@context.__digest__}.js"></script>
    <script>
      Hologram.run({@context.__class__}, "{@context.__state__}")
    </script>
    """
  end
end
