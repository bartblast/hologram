defmodule Hologram.Connection do
  @behaviour WebSock

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Server
  alias Hologram.Socket.Decoder
  alias Hologram.Template.Renderer

  @impl WebSock
  def init(http_conn) do
    {:ok, http_conn}
  end

  @impl WebSock
  def handle_in({"ping", [opcode: :text]}, http_conn) do
    {:reply, :ok, {:text, "pong"}, http_conn}
  end

  @impl WebSock
  def handle_in({message, [opcode: :text]}, http_conn) do
    [type, payload] = Decoder.decode(message)
    {status, body} = dispatch(type, payload)
    {:reply, status, {:text, body}, http_conn}
  end

  @impl WebSock
  def handle_info(_arg, http_conn) do
    {:ok, http_conn}
  end

  defp dispatch("command", payload) do
    %{module: module, name: name, params: params, target: target} = payload

    result = module.command(name, params, %Server{})

    # TODO: handle session & cookies
    next_action =
      case result do
        %Server{next_action: action = %Action{target: nil}} ->
          %{action | target: target}

        %Server{next_action: action} ->
          action

        _fallback ->
          nil
      end

    Encoder.encode_term(next_action)
  end

  defp dispatch("page", payload) do
    opts = [initial_page?: false]

    {html, _component_registry} =
      case payload do
        {page_module, params} ->
          Renderer.render_page(page_module, params, opts)

        page_module ->
          Renderer.render_page(page_module, %{}, opts)
      end

    {:ok, html}
  end
end
