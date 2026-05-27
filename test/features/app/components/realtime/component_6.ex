defmodule HologramFeatureTests.Realtime.Component6 do
  use Hologram.Component

  prop :room, :integer

  def init(props, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, {:room, props.room})
    }
  end

  def template do
    ~HOLO"""
    <p>Widget: <strong id="received-widget">{@received}</strong></p>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end
end
