defmodule Hologram.Compiler.Config do
  def caseConditionExpressionVar, do: "$condition"
  def rightHandSideExpressionVar, do: "window.$hologramRightHandSideExpression"
end
