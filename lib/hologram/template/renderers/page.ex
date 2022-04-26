alias Hologram.Compiler.{Helpers, Serializer}
alias Hologram.Runtime.{PageDigestStore, TemplateStore}
alias Hologram.Template.Renderer
alias Hologram.Utils

defimpl Renderer, for: Atom do
  def render(page_module, conn, _bindings, _slots) do
    layout_module = page_module.layout()
    bindings = aggregate_bindings(page_module, layout_module, conn)
    page_template = TemplateStore.get!(page_module)
    layout_template = TemplateStore.get!(layout_module)

    Renderer.render(layout_template, conn, bindings, default: page_template)
    |> Utils.prepend("<!DOCTYPE html>\n")
  end

  defp aggregate_bindings(page_module, layout_module, conn) do
    class_name = Helpers.class_name(page_module)
    digest = PageDigestStore.get!(page_module)

    bindings =
      layout_module.init(conn)
      |> Map.merge(page_module.init(conn.params, conn))
      |> Map.put(:context, %{
        __class__: class_name,
        __digest__: digest
      })

    serialized_state = Serializer.serialize(bindings)
    context = Map.put(bindings.context, :__state__, serialized_state)
    Map.put(bindings, :context, context)
  end
end
