defmodule Hologram.Compiler.PatternMatching do
  alias Hologram.Compiler.IR

  def deconstruct(ir, side \\ nil, path \\ [])

  def deconstruct(%IR.Symbol{name: name}, :left, path) do
    [[{:binding, name} | path]]
  end

  def deconstruct(ir, :left, path) do
    [[{:left_value, ir} | path]]
  end

  def deconstruct(_ir, :right, path) do
    [[:right_value | path]]
  end
end
