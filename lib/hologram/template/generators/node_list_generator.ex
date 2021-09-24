defmodule Hologram.Template.NodeListGenerator do
  alias Hologram.Template.Generator

  def generate(nodes) do
    js =
      Enum.map(nodes, &Generator.generate/1)
      |> Enum.join(", ")

    if js != "", do: "[ #{js} ]", else: "[]"
  end
end
