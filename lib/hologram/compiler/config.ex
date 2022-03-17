defmodule Hologram.Compiler.Config do
  def caseConditionExpressionVar, do: "$condition"
  def matchAccessJS, do: "window.$hologramMatchAccess"
end
