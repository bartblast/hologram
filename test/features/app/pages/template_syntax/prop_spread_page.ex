defmodule HologramFeatureTests.TemplateSyntax.PropSpreadPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.TemplateSyntax.Component2
  alias HologramFeatureTests.Components.TemplateSyntax.Component3
  alias HologramFeatureTests.Components.TemplateSyntax.Component4

  route "/template-syntax/prop-spread"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :props, %{dom_id: "scenario_3", prop_1: "value_3"})
  end

  def template do
    ~HOLO"""
    <Component2 ...{%{dom_id: "scenario_1", prop_1: "value_1"}} />
    <Component2 ...{dom_id: "scenario_2", prop_1: "value_2"} />
    <Component2 ...{@props} />
    <Component2 ...{dom_id: "scenario_4", prop_1: "value_4", undeclared: "dropped"} />
    <Component2 prop_1="default_5" ...{dom_id: "scenario_5", prop_1: "value_5"} />
    <Component2 ...{dom_id: "scenario_6", prop_1: "default_6"} prop_1="value_6" />
    <Component3 ...{cid: "component_3", dom_id: "scenario_7"} />
    <Component4 html_attrs={%{id: "scenario_8", title: "value_8"}} />
    """
  end
end
