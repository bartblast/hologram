defmodule HologramFeatureTests.SignedOutRulesPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.AccessDeniedError
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Jobs.UpdateMemo

  route "/signed-out-rules"

  layout HologramFeatureTests.Components.DefaultLayout

  state :init_read, :string
  state :result, :string

  # The test seeds one memo with no author that isn't shared, so only trusted code may read it.
  def init(_params, component, _server) do
    memo =
      Memo
      |> one()
      |> DB.read()

    component
    |> put_state(:init_read, visibility(memo))
    |> put_state(:result, "none")
  end

  # No label may be a substring of another - Wallaby matches a button by substring.
  def template do
    ~HOLO"""
    <p>
      <button $click={command: :change_private}> Change private </button>
      <button $click={command: :create_job}> Create job </button>
      <button $click={command: :log_in}> Log in </button>
      <button $click={command: :read_private}> Read private </button>
      <button $click={command: :read_self}> Read self </button>
      <button $click={command: :trusted_change}> Trusted change </button>
      <button $click={command: :trusted_read}> Trusted read </button>
    </p>
    <p>
      Init read: <strong id="init_read"><code>{@init_read}</code></strong>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:change_private, _params, server) do
    result =
      try do
        DB.update!(Memo, private_memo().id, body: "changed_by_command")
        "change_applied"
      rescue
        AccessDeniedError -> "change_refused"
      end

    put_action(server, :show_result, result: result)
  end

  def command(:create_job, _params, server) do
    Job.create!(UpdateMemo, memo_id: private_memo().id)

    put_action(server, :show_result, result: "job_created")
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "stranger@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  def command(:read_private, _params, server) do
    memo = DB.read(Memo, private_memo().id)

    put_action(server, :show_result, result: "read_#{visibility(memo)}")
  end

  # A user may read only their own row, so this tells a signed-in session from a visitor's.
  def command(:read_self, _params, server) do
    user =
      User
      |> filter(email: "stranger@example.com")
      |> one()
      |> DB.read()

    put_action(server, :show_result, result: "read_self_#{visibility(user)}")
  end

  def command(:trusted_change, _params, server) do
    private_memo()
    |> put_attribute(:body, "changed_by_server")
    |> trust()
    |> DB.update!()

    put_action(server, :show_result, result: "trusted_change_applied")
  end

  def command(:trusted_read, _params, server) do
    put_action(server, :show_result, result: "trusted_read_#{visibility(private_memo())}")
  end

  defp private_memo do
    Memo
    |> one()
    |> trust()
    |> DB.read()
  end

  defp visibility(nil), do: "hidden"

  defp visibility(_memo), do: "visible"
end
