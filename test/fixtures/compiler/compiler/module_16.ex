defmodule Hologram.Test.Fixtures.Compiler.Module16 do
  use Hologram.Component

  def template do
    ~H"""
    <div>
      <span test_attr={Hologram.Test.Fixtures.Compiler.Module8.test_fun_8()}></span>
    </div>
    """
  end
end
