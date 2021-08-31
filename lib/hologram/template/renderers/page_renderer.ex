alias Hologram.Compiler.{Helpers, Serializer}
alias Hologram.Template.{Builder, Renderer}
alias Hologram.Utils

defimpl Renderer, for: Atom do
  def render(module, _params, slots) do
    state = init_state(module)
    layout = module.layout()

    Builder.build(module, layout)
    |> Renderer.render(state, slots)
    |> Utils.prepend("<!DOCTYPE html>")
  end

  # DEFER: optimize, e.g. load the manifest in config
  defp get_digest(module) do
    File.cwd!() <> "/priv/static/hologram/manifest.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("#{module}")
  end

  defp init_state(module) do
    class_name = Helpers.class_name(module)
    digest = get_digest(module)

    # DEFER: pass page params to state function
    state =
      module.state()
      |> Map.put(:context, %{
        __class__: class_name,
        # TODO: use __digest__ interpolation instead of __page_src__
        __src__: "/hologram/page-#{digest}.js"
      })

    serialized_state = Serializer.serialize(state)
    context = Map.put(state.context, :__state__, serialized_state)
    Map.put(state, :context, context)
  end
end
