defmodule Hologram do
  @env Application.compile_env!(:hologram, :env)

  def env, do: @env
end
