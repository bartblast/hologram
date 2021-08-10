alias Hologram.Compiler.{Helpers, Serializer}
alias Hologram.Template.{Builder, Renderer}

defimpl Renderer, for: Atom do
  def render(module, _params) do
    # DEFER: pass params to state function
    state = module.state()

    Builder.build(module)
    |> Renderer.render(state)
    |> render_layout(module, state)
  end

  # DEFER: optimize, e.g. load the manifest in config
  defp get_page_js_digest(module) do
    File.cwd!() <> "/priv/static/hologram/manifest.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("#{module}")
  end

  defp render_layout(inner_html, module, state) do
    digest = get_page_js_digest(module)
    class_name = Helpers.class_name(module)
    serialized_state = Serializer.serialize(state)

    part_1 =
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <script src="/js/hologram.js"></script>
        <script src="/hologram/page-#{digest}.js"></script>
        <script>
          Hologram.run(window, #{class_name}, #{serialized_state})
        </script>
      </head>
    """

    # fix indentation
    part_2 =
      String.split(inner_html, "\n")
      |> Enum.map(&("  " <> &1))
      |> Enum.join("\n")

    part_1 <> part_2 <> "\n</html>"
  end
end
