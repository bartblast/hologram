defmodule HologramFeatureTests.TemplateSyntax.DynamicComponentPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.TemplateSyntax.Component2
  alias HologramFeatureTests.Components.TemplateSyntax.Component5
  alias HologramFeatureTests.Components.TemplateSyntax.Component6

  route "/template-syntax/dynamic-component"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, module_1: Component2, module_2: Component5, module_3: nil)
  end

  def template do
    ~HOLO"""
    <{@module_1} dom_id="scenario_1" prop_1="value_1" />
    <{@module_1} ...{dom_id: "scenario_2", prop_1: "value_2"} />
    <{@module_2} dom_id="scenario_3">value_3</{@module_2}>
    <button $click={command: :load_module_3} id="scenario_4_button">Load module 3</button>
    {%if @module_3}<{@module_3} dom_id="scenario_4" />{/if}
    """
  end

  def action(:put_module_3, params, component) do
    put_state(component, :module_3, params.module)
  end

  def command(:load_module_3, _params, server) do
    put_action(server, :put_module_3, module: Component6)
  end
end
