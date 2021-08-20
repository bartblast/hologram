defmodule Hologram.Test.Fixtures.Compiler.Module10 do
  use Hologram.Component

  def template do
    ~H"""
    <Hologram.Test.Fixtures.Compiler.Module11 />
    """
  end
end
