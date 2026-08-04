defmodule App1.HomePage do
  use Hologram.Page

  route "/"

  layout App1.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Umbrella home page</h1>
    <p>
      <button $click="fetch_app_2_message">Fetch app_2 message</button>
    </p>
    <p>
      Result: <strong id="result">{@result}</strong>
    </p>
    """
  end

  def action(:fetch_app_2_message, _params, component) do
    put_state(component, :result, App2.message())
  end
end
