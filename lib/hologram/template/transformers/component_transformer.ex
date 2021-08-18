defmodule Hologram.Template.ComponentTransformer do
  alias Hologram.Compiler.{Helpers, Resolver}
  alias Hologram.Template.Document.Component

  def transform(module_name, props, children, aliases) do
    module =
      Helpers.module_segments(module_name)
      |> Resolver.resolve(aliases)

    props = transform_props(props)

    %Component{module: module, props: props, children: children}
  end

  defp transform_props(props) do
    Enum.map(props, fn {key, value} -> {String.to_atom(key), value} end)
    |> Enum.into(%{})
  end
end
