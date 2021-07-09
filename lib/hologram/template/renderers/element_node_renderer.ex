defmodule Hologram.Template.ElementNodeRenderer do
  alias Hologram.Template.Renderer

  @pruned_attrs [:on_click]

  def render(tag, attrs, children, state) do
    attrs_html = render_attrs(attrs)
    children_html = render_children(children, state)

    "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
  end

  defp render_attrs(attrs) do
    Enum.reject(attrs, fn {key, _} -> key in @pruned_attrs end)
    |> Enum.map(fn {key, value} -> " #{key}=\"#{value}\"" end)
    |> Enum.join("")
  end

  defp render_children(children, state) do
    Enum.map(children, fn child -> Renderer.render(child, state) end)
    |> Enum.join("")
  end
end
