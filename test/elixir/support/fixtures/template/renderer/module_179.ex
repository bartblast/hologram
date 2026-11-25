# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module179 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity
  alias Hologram.Test.Fixtures.Template.Renderer.Module157
  alias Hologram.Test.Fixtures.Template.Renderer.Module180

  route "/hologram-test-fixtures-template-renderer-module179"

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  state :change_each_time, :boolean
  state :child_cid, :string
  state :user_id, :string

  derived :page_entities, [PolicyEntity], fn -> sort(PolicyEntity, priority) end

  @impl Page
  def init(params, component, server) do
    component =
      component
      |> put_state(:user_id, params.user_id)
      |> put_state(:change_each_time, Map.get(params, :change_each_time, false))
      |> put_state(:child_cid, child_cid(params))

    # Written before the child's init/3 writes the same key.
    if Map.get(params, :signs_in_over, false) do
      {component, put_session(server, :signed_in_by, "module_179")}
    else
      component
    end
  end

  # A child named anew on every render is another component each time.
  defp child_cid(%{renames_child: true}) do
    inits = Process.get(:module_179_inits, 0) + 1
    Process.put(:module_179_inits, inits)

    "signing_in_#{inits}"
  end

  defp child_cid(_params), do: "signing_in"

  @impl Page
  def template do
    ~HOLO"""
    page = {Enum.map_join(@page_entities, ",", &Integer.to_string(&1.priority))};
    <Module157 />
    <Module180 cid={@child_cid} user_id={@user_id} change_each_time={@change_each_time} />
    """
  end
end
