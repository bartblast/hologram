defmodule Hologram.Test.Fixtures.Compiler.Module14 do
  use Hologram.Component

  def template do
    ~H"""
    <Hologram.Test.Fixtures.Compiler.Module11 test_prop={Hologram.Test.Fixtures.Compiler.Module8.test_fun_8()} />
    """
  end
end
