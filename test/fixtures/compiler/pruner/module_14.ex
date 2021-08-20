defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module14 do
  use Hologram.Page

  def template do
    ~H"""
    <div>
      <span test_attr={Hologram.Test.Fixtures.Compiler.Pruner.Module8.test_8()}></span>
    </div>
    """
  end
end
