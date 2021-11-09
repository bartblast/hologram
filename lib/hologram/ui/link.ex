defmodule Hologram.UI.Link do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <a href={@to.route()} on_click.command={:__redirect__, page: @to} id={@id} class={@class}><slot /></a>
    """
  end
end
