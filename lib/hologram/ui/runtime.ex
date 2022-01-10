defmodule Hologram.UI.Runtime do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <script>
      window.hologramArgs = \{
        class: "{@context.__class__}",
        state: "{@context.__state__}"
      \}
    </script>
    <script src="/hologram/manifest.js"></script>
    <script src={static_path("/hologram/runtime.js")}></script>
    <script src="/hologram/page-{@context.__digest__}.js"></script>
    """
  end
end
