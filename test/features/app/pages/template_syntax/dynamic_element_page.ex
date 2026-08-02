defmodule HologramFeatureTests.TemplateSyntax.DynamicElementPage do
  use Hologram.Page

  route "/template-syntax/dynamic-element"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, clicked?: false, level: "h2")
  end

  def template do
    ~HOLO"""
    <{@level} id="scenario_1">value_1</{@level}>
    <{"button"} $click="record_click" id="scenario_2">value_2</{"button"}>
    <p id="scenario_2_result">clicked? = {@clicked?}</p>
    """
  end

  def action(:record_click, _params, component) do
    put_state(component, :clicked?, true)
  end
end
