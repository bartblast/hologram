defmodule HologramFeatureTests.TemplateSyntax.DynamicComponentSwapPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.TemplateSyntax.Component7
  alias HologramFeatureTests.Components.TemplateSyntax.Component8

  route "/template-syntax/dynamic-component-swap"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :module, Component7)
  end

  def template do
    ~HOLO"""
    <button $click="swap_module" id="swap_button">Swap</button>
    <{@module} cid="swappable" />
    """
  end

  def action(:swap_module, _params, component) do
    new_module = if component.state.module == Component7, do: Component8, else: Component7
    put_state(component, :module, new_module)
  end
end
