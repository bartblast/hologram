defmodule Hologram.UI.Link do
  use Hologram.Component

  def init(_props) do
    %{}
  end

  def template do
    ~H"""
    <a href={@to.route()} on:click.command={:__redirect__, page: @to} id={if @bindings[:id] do @bindings[:id] else false end} class={if @bindings[:class] do @bindings[:class] else false end}><slot /></a>
    """
  end
end
