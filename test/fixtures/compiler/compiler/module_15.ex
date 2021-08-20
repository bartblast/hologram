defmodule Hologram.Test.Fixtures.Compiler.Module15 do
  use Hologram.Component

  def template do
    ~H"""
    <div test_attr={Hologram.Test.Fixtures.Compiler.Module8.test_fun_8()}></div>
    """
  end
end
