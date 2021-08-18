defmodule Hologram.Template.ElementNodeTransformer do
  alias Hologram.Template.Document.ElementNode

  def transform(tag, children, attrs) do
    attrs = transform_attrs(attrs)
    %ElementNode{tag: tag, children: children, attrs: attrs}
  end

  defp transform_attrs(attrs) do
    Enum.map(attrs, fn {key, value} ->
      [name | modifiers] = String.split(key, ".")
      name = String.to_atom(name)
      modifiers = Enum.map(modifiers, &String.to_atom/1)
      {name, %{value: value, modifiers: modifiers}}
    end)
    |> Enum.into(%{})
  end
end
