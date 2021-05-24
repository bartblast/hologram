defmodule Hologram.Template.ElementNodeRenderer do
  alias Hologram.Template.Renderer

  def render(tag, attrs, children, state) do
    attrs_html =
      Enum.map(attrs, fn {key, value} -> " #{render_attr_name(key)}=\"#{value}\"" end)
      |> Enum.join("")

    children_html =
      Enum.map(children, fn child -> Renderer.render(child, state) end)
      |> Enum.join("")

    "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
  end

  def render_attr_name(key) do
    case key do
      ":click" ->
        "holo-click"

      _ ->
        key
    end
  end
end
