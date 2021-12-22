defmodule Hologram.UI.Runtime do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <script src={static_path("/hologram/runtime.js")}></script>
    <script src="/hologram/page-{@context.__digest__}.js"></script>
    <script>
      Hologram.run({@context.__class__}, "{@context.__state__}")
    </script>
    """
  end
end
