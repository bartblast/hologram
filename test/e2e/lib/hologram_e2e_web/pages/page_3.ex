defmodule Hologram.E2E.Page3 do
  use Hologram.Page
  alias Hologram.E2E.{Component1, Component2}, warn: false

  route "/e2e/page-3"

  def init do
    %{
      a: "abc",
      b: "bcd",
      c: "cde"
    }
  end

  def template do
    ~H"""
    <div>
      in page template: {@a}
      <Component1>
        in component 1 slot: {@b}
        <Component2>
          in component 2 slot: {@c}
        </Component2>
      </Component1>
      <button id="update-button" on:click="update_c">Update</button>
    </div>
    """
  end

  def action(:update_c, _params, state) do
    put(state, :c, "xyz")
  end
end
