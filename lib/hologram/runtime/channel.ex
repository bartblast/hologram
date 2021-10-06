defmodule Hologram.Runtime.Channel do
  use Phoenix.Channel

  alias Hologram.Compiler.{Decoder, Serializer}
  alias Hologram.Template.Renderer

  def join("hologram", _, socket) do
    {:ok, socket}
  end

  def handle_in("command", %{"target_module" => target_module} = payload, socket) do
    target_module = Decoder.decode(target_module)

    response =
      execute_command(target_module, payload)
      |> build_response(target_module)
      |> Serializer.serialize()

    {:reply, {:ok, response}, socket}
  end

  defp build_response({action, params}, target_module) do
    {action, Enum.into(params, %{}), target_module}
  end

  defp build_response(action, target_module) do
    {action, %{}, target_module}
  end

  defp execute_command(target_module, %{"name" => name, "params" => params}) do
    name = Decoder.decode(name)

    params =
      Decoder.decode(params)
      |> Enum.into(%{})

    if name == :__redirect__ do
      html = Renderer.render(params.page, %{})
      # DEFER: inject params
      url = params.page.route()
      {:__redirect__, html: html, url: url}
    else
      apply(target_module, :command, [name, params])
    end
  end
end
