defmodule Hologram.Test.Fixtures.Commons.Parser.Implementation do
  use Hologram.Commons.Parser

  @impl Hologram.Commons.Parser
  def parse(code)

  def parse("valid_code") do
    {:ok, :dummy_result}
  end

  def parse(_code) do
    {:error, :dummy_error_details}
  end
end
