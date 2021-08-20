defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module12 do
  use Hologram.Page

  def template do
    ~H"""
      <div test_attr={Hologram.Test.Fixtures.Compiler.Pruner.Module8.test_8()}></div>
    """
  end
end
