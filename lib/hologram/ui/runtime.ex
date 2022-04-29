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
        context: {@__context__.__serialized_context__}
        state: ###SERIALIZED_STATE###
      \}
    </script>
    <script src="/hologram/manifest.js"></script>
    <script src={static_path("/hologram/runtime.js")}></script>
    <script src="/hologram/page-{@__context__.__digest__}.js"></script>
    """
  end
end
