# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module33 do
  use Hologram.Component

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Role.Module1, as: Role1

  @impl Component
  def command(:my_command_creating_entity, _params, server) do
    Module1
    |> Entity.new()
    |> DB.create!()

    %{server | next_action: nil}
  end

  def command(:my_command_granting_global_role, %{user_id: user_id}, server) do
    Auth.grant_role(user_id, Role1)

    %{server | next_action: nil}
  end

  def command(:my_command_revoking_role, params, server) do
    %{resource_id: resource_id, user_id: user_id} = params

    Auth.revoke_role(user_id, %Module1{id: resource_id}, :owner)

    %{server | next_action: nil}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
