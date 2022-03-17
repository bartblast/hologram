defmodule Hologram.Compiler.Config do
  def caseConditionExpressionVar, do: "$condition"
  def match_access_js, do: "window.$hologramMatchAccess"
end
