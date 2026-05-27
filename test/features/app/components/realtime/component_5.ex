defmodule HologramFeatureTests.Realtime.Component5 do
  use Hologram.Component

  @channel {:room, 18}

  def init(_props, component, server) do
    {
      put_state(component, broadcasts: "none", subscriptions: "none"),
      put_subscription(server, @channel)
    }
  end

  def template do
    ~HOLO"""
    <p>Broadcasts: <strong id="broadcasts-component">{@broadcasts}</strong></p>
    <p>Subscriptions: <strong id="subscriptions-component">{@subscriptions}</strong></p>
    <button $click={command: :report}>Report</button>
    """
  end

  def action(:report, params, component) do
    put_state(component,
      broadcasts: params[:broadcasts],
      subscriptions: params[:subscriptions]
    )
  end

  def command(:report, _params, server) do
    put_action(server, :report,
      broadcasts: inspect(server.broadcasts),
      subscriptions: inspect(server.subscriptions)
    )
  end
end
