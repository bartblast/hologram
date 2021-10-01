defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module20 do
  use Hologram.Page

  route("/test-route")

  def template do
    ~H"""
    """
  end

  def fun_1 do
    1
  end

  def fun_2 do
    2
  end

  def fun_3 do
    3
  end
end
