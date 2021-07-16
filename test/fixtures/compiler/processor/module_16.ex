defmodule Hologram.Test.Fixtures.Compiler.Processor.Module16 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Processor.Module9

  def template do
    ~H"""
    test_text
    <Module9></Module9>
    test_text
    """
  end

  # prevent unused alias compiler warning
  Module9
end
