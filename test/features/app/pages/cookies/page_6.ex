defmodule HologramFeatureTests.Cookies.Page6 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/cookies/6"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, command_executed?: false, cookie_value: nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :set_cookie_with_default_settings}>Set cookie with default settings</button>
      <button $click={command: :set_cookie_with_custom_settings}>Set cookie with custom settings</button>
      <button $click={command: :read_string_encoded_cookie}>Read string-encoded cookie</button>
      <button $click={command: :read_hologram_encoded_cookie}>Read Hologram-encoded cookie</button>
    </p>
    <p>
      command_executed? = {inspect(@command_executed?)}, cookie_value = {inspect(@cookie_value)}
    </p>
    """
  end

  def action(:toggle_command_executed_flag, _params, component) do
    put_state(component, :command_executed?, not component.state.command_executed?)
  end

  def action(:update_state_with_cookie_value, params, component) do
    put_state(component, command_executed?: true, cookie_value: params.cookie_value)
  end

  def command(:read_hologram_encoded_cookie, _params, server) do
    cookie_value =
      server
      |> get_cookie("hologram_encoded_cookie_key")
      |> Map.put(:c, 3)

    put_action(server, :update_state_with_cookie_value, cookie_value: cookie_value)
  end

  def command(:read_string_encoded_cookie, _params, server) do
    cookie_value = get_cookie(server, "string_encoded_cookie_key")
    put_action(server, :update_state_with_cookie_value, cookie_value: cookie_value)
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
