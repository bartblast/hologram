defmodule HologramFeatureTests.TemplateSyntax.DynamicComponentPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.TemplateSyntax.Component2
  alias HologramFeatureTests.Components.TemplateSyntax.Component5

  route "/template-syntax/dynamic-component"

  layout HologramFeatureTests.Components.DefaultLayout

  # Module literals in init/3 don't create client reachability - Component2 is bundled
  # because scenario 1 spells it as a literal in the template.
  def init(_params, component, _server) do
    put_state(component, :module, Component2)
  end

  def template do
    ~HOLO"""
    <{Component2} dom_id="scenario_1" prop_1="value_1" />
    <{@module} ...{dom_id: "scenario_2", prop_1: "value_2"} />
    <{Component5} dom_id="scenario_3">value_3</{Component5}>
    """
  end
end
