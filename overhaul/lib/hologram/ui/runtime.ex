# TODO: test

defmodule Hologram.UI.Runtime do
  use Hologram.Component

  def init(_props) do
    %{}
  end

  def template do
    ~H"""
    <script>
      window.hologramArgs = \{
        class: "{@__context__.__class__}",
        digest: "{@__context__.__digest__}",
        state: {@__context__.__state__}
      \}
    </script>
    <script src="/hologram/manifest.js"></script>
    <script src={static_path("/hologram/runtime.js")}></script>
    <script src="/hologram/page-{@__context__.__digest__}.js"></script>
    """
  end
end
