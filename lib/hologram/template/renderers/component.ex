alias Hologram.Runtime.TemplateStore
alias Hologram.Template.Evaluator
alias Hologram.Template.Renderer
alias Hologram.Template.VDOM.Component
alias Hologram.Template.VDOM.Expression

defimpl Renderer, for: Component do
  def render(component, conn, outer_bindings, _) do
    props = evaluate_props(component.props, outer_bindings)
    initial_state = initialize_state(component.module, props, conn)
    bindings = Map.merge(props, initial_state)
    slots = {outer_bindings, default: component.children}

    {html, nested_initial_state} =
      TemplateStore.get!(component.module)
      |> Renderer.render(conn, bindings, slots)

    state = aggregate_state(nested_initial_state, initial_state, props)
    {html, state}
  end

  defp aggregate_state(nested_initial_state, initial_state, %{id: id}) do
    Map.put(nested_initial_state, String.to_atom(id), initial_state)
  end

  defp aggregate_state(nested_initial_state, _, _), do: nested_initial_state

  defp evaluate_props(props, outer_bindings) do
    Enum.map(props, fn {key, value} ->
      {key, evaluate_value(value, outer_bindings)}
    end)
    |> Enum.into(%{})
  end

  defp evaluate_value([%Expression{} = expr], outer_bindings) do
    Evaluator.evaluate(expr, outer_bindings)
  end

  defp evaluate_value(parts, outer_bindings) do
    Enum.reduce(parts, "", fn part, acc ->
      evaluated = Evaluator.evaluate(part, outer_bindings) |> to_string()
      acc <> evaluated
    end)
  end

  defp initialize_state(module, %{id: _} = props, conn) do
    if function_exported?(module, :init, 2) do
      module.init(props, conn)
    else
      module.init(props)
    end
  end

  defp initialize_state(_, _, _), do: %{}
end
