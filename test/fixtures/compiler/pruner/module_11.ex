defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module11 do
  use Hologram.Page

  def template do
    ~H"""
      <Hologram.Test.Fixtures.Compiler.Pruner.Module4 test_prop={Hologram.Test.Fixtures.Compiler.Pruner.Module8.test_8()} />
    """
  end
end
