# Used only in client tests.
defmodule Hologram.Test.Fixtures.Template.Renderer.Module60 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module61

  @impl Component
  def template do
    ~H"""
    <Module61 cid="component_61">
      <div>
        <button $click="my_action">Click me</button>
      </div>      
    </Module61>
    """
  end
end
