alias Hologram.Compiler.Helpers
alias Hologram.Template.Document.{Component, Expression}
alias Hologram.Template.{Builder, Evaluator, Renderer}

defimpl Renderer, for: Component do
  def render(component, state, _) do
    state =
      if Helpers.is_layout?(component.module_def) do
        state
      else
        evaluate_state(state, component.props)
      end
      |> Map.put(:context, state.context)

    Builder.build(component.module)
    |> Renderer.render(state, default: component.children)
  end

  defp evaluate_state(state, props) do
    Enum.map(props, fn {key, value} ->
      {key, evaluate_value(value, state)}
    end)
    |> Enum.into(%{})
  end

  defp evaluate_value([%Expression{} = expr], state) do
    Evaluator.evaluate(expr, state)
  end

  defp evaluate_value(value, state) do
    Enum.reduce(value, "", fn part, acc ->
      evaluated = Evaluator.evaluate(part, state) |> to_string()
      acc <> evaluated
    end)
  end
end
