defmodule Hologram.E2E.Page8 do
  use Hologram.Page

  route "/e2e/page-8"

  def init do
    %{
      field_1: "",
      field_2: ""
    }
  end

  def template do
    ~H"""
    <h1>Page 8</h1>
    <form on:submit="submit">
      <input id="input-1" type="text" name="field_1" />
      <input id="input-2" type="text" name="field_2" />
      <button id="submit-button">Submit</button>
    </form>
    <div id="text-1">Field 1 value = {@field_1}</div>
    <div id="text-2">Field 2 value = {@field_2}</div>
    """
  end

  def action(:submit, params, state) do
    put(state, :field_1, params.event.field_1)
    |> put(:field_2, params.event.field_2)
  end
end
