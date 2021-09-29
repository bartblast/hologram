alias Hologram.Template.Encoder

defimpl Encoder, for: List do
  def encode(nodes) do
    js =
      Enum.map(nodes, &Encoder.encode/1)
      |> Enum.join(", ")

    if js != "", do: "[ #{js} ]", else: "[]"
  end
end
