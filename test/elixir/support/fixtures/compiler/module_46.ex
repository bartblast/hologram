# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module46 do
  use Hologram.Component

  def template do
    cond do
      System.get_env("HOLOGRAM_WIDE") ->
        ~HOLO"""
        <p $ref="wide"></p>
        """

      System.get_env("HOLOGRAM_TALL") ->
        ~HOLO"""
        <p $ref="tall"></p>
        """

      true ->
        ~HOLO"""
        <p $ref="narrow"></p>
        """
    end
  end
end
