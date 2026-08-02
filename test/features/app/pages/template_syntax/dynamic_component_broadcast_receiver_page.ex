defmodule HologramFeatureTests.TemplateSyntax.DynamicComponentBroadcastReceiverPage do
  use Hologram.Page

  route "/template-syntax/dynamic-component-broadcast-receiver"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel :template_syntax_dynamic_component

  def init(_params, component, server) do
    {
      put_state(component, :module, nil),
      put_subscription(server, @channel)
    }
  end

  def template do
    ~HOLO"""
    {%if @module}<{@module} dom_id="scenario_5" />{/if}
    """
  end

  def action(:put_module, params, component) do
    put_state(component, :module, params.module)
  end
end
