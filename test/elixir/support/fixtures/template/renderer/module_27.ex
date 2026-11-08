defmodule Hologram.Test.Fixtures.Template.Renderer.Module27 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module27"

  layout Hologram.Test.Fixtures.Template.Renderer.Module26

  state :prop_1, :string
  state :prop_2, :string
  state :prop_3, :string

  @impl Page
  def init(_params, component, _server) do
    put_state(component, prop_1: "prop_value_1", prop_2: "prop_value_2", prop_3: "prop_value_3")
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
