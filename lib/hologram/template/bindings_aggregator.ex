alias Hologram.Template.Evaluator
alias Hologram.Template.VDOM.{Component, Expression}

defmodule Hologram.Template.BindingsAggregator do
  def aggregate(%Component{} = component, outer_bindings) do
    if component.module_def.layout? do
      outer_bindings
    else
      evaluate_props(component.props, outer_bindings)
      |> Map.put(:context, outer_bindings.context)
    end
    |> Map.merge(component.module.init())
  end

  defp evaluate_props(props, bindings) do
    Enum.map(props, fn {key, value} ->
      {key, evaluate_value(value, bindings)}
    end)
    |> Enum.into(%{})
  end

  defp evaluate_value([%Expression{} = expr], bindings) do
    Evaluator.evaluate(expr, bindings)
  end

  defp evaluate_value(parts, bindings) do
    Enum.reduce(parts, "", fn part, acc ->
      evaluated = Evaluator.evaluate(part, bindings) |> to_string()
      acc <> evaluated
    end)
  end
end
