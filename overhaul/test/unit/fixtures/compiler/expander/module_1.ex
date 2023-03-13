defmodule Hologram.Test.Fixtures.Compiler.Expander.Module1 do
  def fun_1, do: nil
  def fun_1(_param_1), do: nil
  def fun_1(_param_1, _param_2), do: nil

  def fun_2(_param_1), do: nil

  def fun_3(_param_1, _param_2), do: nil

  def sigil_a(_param_1, _param_2), do: nil
  def sigil_b(_param_1, _param_2), do: nil

  defmacro macro_1, do: nil
  defmacro macro_1(_param_1), do: nil
  defmacro macro_1(_param_1, _param_2), do: nil

  defmacro macro_2(_param_1), do: nil

  defmacro macro_3(_param_1, _param_2), do: nil

  defmacro sigil_c(_param_1, _param_2), do: nil
  defmacro sigil_d(_param_1, _param_2), do: nil
end
