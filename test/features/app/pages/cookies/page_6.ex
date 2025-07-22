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
      <button $click={command: :write_cookie_with_default_settings}>Write cookie with default settings</button>
      <button $click={command: :write_cookie_with_custom_settings}>Write cookie with custom settings</button>
      <button $click={command: :read_string_encoded_cookie}>Read string-encoded cookie</button>
      <button $click={command: :read_hologram_encoded_cookie}>Read Hologram-encoded cookie</button>
      <button $click={command: :delete_cookie}>Delete cookie</button>
    </p>
    <p>
      command_executed? = {inspect(@command_executed?)}, cookie_value = {inspect(@cookie_value)}
    </p>
    """
  end

  def action(:set_command_executed_flag, _params, component) do
    put_state(component, :command_executed?, true)
  end

  def action(:update_state_with_cookie_value, params, component) do
    put_state(component, command_executed?: true, cookie_value: params.cookie_value)
  end

  def command(:delete_cookie, _params, server) do
    server
    |> delete_cookie("cookie_key")
    |> put_action(:set_command_executed_flag)
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

  def command(:write_cookie_with_custom_settings, _params, server) do
    opts = [
      http_only: false,
      path: __MODULE__.__route__(),
      same_site: :strict,
      secure: false
    ]

    server
    |> put_cookie("custom_settings_cookie_key", "custom_settings_cookie_value", opts)
    |> put_action(:set_command_executed_flag)
  end

  def command(:write_cookie_with_default_settings, _params, server) do
    server
    |> put_cookie("default_settings_cookie_key", "default_settings_cookie_value")
    |> put_action(:set_command_executed_flag)
  end
end
