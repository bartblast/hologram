defmodule HologramFeatureTests.TemplateSyntax.DynamicComponentBroadcastSenderPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.TemplateSyntax.Component9

  route "/template-syntax/dynamic-component-broadcast-sender"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel :template_syntax_dynamic_component

  def template do
    ~HOLO"""
    <button $click={command: :broadcast_module} id="broadcast_button">Broadcast module</button>
    """
  end

  # Component9 is referenced here only, so the receiver page can render it just
  # when the compiler puts broadcast-referenced components into the runtime bundle.
  def command(:broadcast_module, _params, server) do
    put_broadcast(server, @channel, :put_module, module: Component9)
  end
end
