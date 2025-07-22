defmodule HologramFeatureTests.Cookies.Page6 do
  use Hologram.Page

  route "/cookies/6"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :command_executed?, false)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :set_cookie_with_default_settings}>Set cookie with default settings</button>
      <button $click={command: :set_cookie_with_custom_settings}>Set cookie with custom settings</button>
    </p>
    <p>
      command_executed? = {@command_executed?}
    </p>
    """
  end

  def action(:toggle_command_executed_flag, _params, component) do
    put_state(component, :command_executed?, not component.state.command_executed?)
  end

  def command(:set_cookie_with_custom_settings, _params, server) do
    opts = [
      http_only: false,
      path: __MODULE__.__route__(),
      same_site: :strict,
      secure: false
    ]

    server
    |> put_cookie("cookie_key", "cookie_value", opts)
    |> put_action(:toggle_command_executed_flag)
  end

  def command(:set_cookie_with_default_settings, _params, server) do
    server
    |> put_cookie("cookie_key", "cookie_value")
    |> put_action(:toggle_command_executed_flag)
  end
end
