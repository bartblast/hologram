defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module61 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module62

  def template do
    ~H"""
    """
  end

  def action do
    Module62.test_fun_62a()
  end
end
