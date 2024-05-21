defmodule Hologram.Channel do
  use Phoenix.Channel

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Server
  alias Hologram.Socket.Decoder

  @impl Phoenix.Channel
  def join("hologram", _payload, socket) do
    {:ok, socket}
  end

  @impl Phoenix.Channel
  def handle_in("command", payload, socket) do
    %{module: module, name: name, params: params, target: target} = Decoder.decode(payload)

    result = apply(module, :command, [name, params, %Server{}])

    # TODO: handle session & cookies
    reply =
      case result do
        %Server{next_action: action = %Action{target: nil}} ->
          %{action | target: target}

        %Server{next_action: action} ->
          action

        _fallback ->
          nil
      end
      |> Encoder.encode_term()

    {:reply, {:ok, reply}, socket}
  end
end
