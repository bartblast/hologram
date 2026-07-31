defmodule HologramFeatureTests.TemplateSyntax.AttributeSpreadPage do
  use Hologram.Page

  route "/template-syntax/attribute-spread"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :attrs, %{title: "value_3"})
  end

  def template do
    ~HOLO"""
    <span id="scenario_1" ...{%{title: "value_1"}}>map value</span>
    <span id="scenario_2" ...{title: "value_2"}>keyword shorthand value</span>
    <span id="scenario_3" ...{@attrs}>state value</span>
    <span id="scenario_4" ...{data: [user_id: "value_4"]}>nested value</span>
    <span id="scenario_5" ...{title: nil, class: "value_5"}>nil entry</span>
    <span id="scenario_6" title="default_6" ...{title: "value_6"}>literal before spread</span>
    <span id="scenario_7" ...{title: "default_7"} title="value_7">literal after spread</span>
    <span id="scenario_8" ...{title: "default_8"} ...{title: "value_8"}>two spreads</span>
    """
  end
end
