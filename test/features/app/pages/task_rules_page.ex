defmodule HologramFeatureTests.TaskRulesPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Auth
  alias Hologram.MisuseError
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.User

  # Bounds that stay above the 30 seconds a test waits in the browser, so a slow run fails there.
  @await_timeout 60_000
  @hold_cap 120_000

  route "/task-rules"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  # No label may be a substring of another - Wallaby matches a button by substring.
  def template do
    ~HOLO"""
    <p>
      <button $click={command: :bare_change}> Bare change </button>
      <button $click={command: :bare_read}> Bare read </button>
      <button $click={command: :carried_change}> Carried change </button>
      <button $click={command: :carried_read}> Carried read </button>
      <button $click={command: :hold_bare}> Hold bare </button>
      <button $click={command: :hold_carried}> Hold carried </button>
      <button $click={command: :hold_supervised}> Hold supervised </button>
      <button $click={command: :release_held}> Release held </button>
      <button $click={command: :sign_in_author}> Sign in author </button>
      <button $click={command: :sign_in_stranger}> Sign in stranger </button>
      <button $click={command: :trusted_read}> Trusted read </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:bare_change, _params, server) do
    memo_id = memo().id

    result =
      fn -> refusing(fn -> change(memo_id) end) end
      |> Task.async()
      |> Task.await(@await_timeout)

    put_action(server, :show_result, result: "bare_change_#{result}")
  end

  def command(:bare_read, _params, server) do
    memo_id = memo().id

    result =
      fn -> refusing(fn -> read(memo_id) end) end
      |> Task.async()
      |> Task.await(@await_timeout)

    put_action(server, :show_result, result: "bare_read_#{result}")
  end

  def command(:carried_change, _params, server) do
    memo_id = memo().id

    result =
      fn ->
        try do
          change(memo_id)
        rescue
          Hologram.AccessDeniedError -> "denied"
        end
      end
      |> Auth.as_current_user()
      |> Task.async()
      |> Task.await(@await_timeout)

    put_action(server, :show_result, result: "carried_change_#{result}")
  end

  def command(:carried_read, _params, server) do
    memo_id = memo().id

    result =
      fn -> read(memo_id) end
      |> Auth.as_current_user()
      |> Task.async()
      |> Task.await(@await_timeout)

    put_action(server, :show_result, result: "carried_read_#{result}")
  end

  # Started and left running, so the test can let it read after later requests have been served.
  def command(:hold_bare, _params, server) do
    memo_id = memo().id

    {:ok, task} =
      self()
      |> holding(fn -> refusing(fn -> read(memo_id) end) end)
      |> Task.start()

    await_held(task)

    put_action(server, :show_result, result: "holding_bare")
  end

  def command(:hold_carried, _params, server) do
    memo_id = memo().id

    {:ok, task} =
      self()
      |> holding(fn -> "#{user_name(Auth.user_id())}_#{read(memo_id)}" end)
      |> Auth.as_current_user()
      |> Task.start()

    await_held(task)

    put_action(server, :show_result, result: "holding_carried")
  end

  # The test starts the supervisor, outside any request, so the task inherits nothing from this
  # process and can only be told apart by what this process has done.
  def command(:hold_supervised, _params, server) do
    memo_id = memo().id

    {:ok, task} =
      Task.Supervisor.start_child(
        __MODULE__.TaskSupervisor,
        holding(self(), fn -> refusing(fn -> read(memo_id) end) end)
      )

    await_held(task)

    put_action(server, :show_result, result: "holding_supervised")
  end

  # Lets the held task read while this request is served, for whoever it arrived as. The result
  # tells whether this request came over the connection the task was started from.
  def command(:release_held, _params, server) do
    holder = :global.whereis_name({__MODULE__, :held})
    monitor = Process.monitor(holder)
    send(holder, {:go, self()})

    receive do
      {:held_result, result, holder_command_pid} ->
        Process.demonitor(monitor, [:flush])
        connection = if holder_command_pid == self(), do: "reused", else: "fresh"

        put_action(server, :show_result, result: "released_#{result}_#{connection}")

      {:DOWN, ^monitor, :process, ^holder, reason} ->
        raise "the held task ended without answering: #{inspect(reason)}"
    after
      @await_timeout -> raise "the held task didn't answer"
    end
  end

  def command(:sign_in_author, _params, server) do
    sign_in(server, "author@example.com", "signed_in_author")
  end

  def command(:sign_in_stranger, _params, server) do
    sign_in(server, "stranger@example.com", "signed_in_stranger")
  end

  def command(:trusted_read, _params, server) do
    result =
      fn ->
        Memo
        |> one()
        |> trust()
        |> DB.read()
        |> visibility()
      end
      |> Task.async()
      |> Task.await(@await_timeout)

    put_action(server, :show_result, result: "trusted_read_#{result}")
  end

  defp await_held(task) do
    monitor = Process.monitor(task)

    receive do
      :held ->
        Process.demonitor(monitor, [:flush])

      {:DOWN, ^monitor, :process, ^task, reason} ->
        raise "the task ended before holding: #{inspect(reason)}"
    after
      @await_timeout -> raise "the task didn't start holding"
    end
  end

  # Unpins the memo, which only its author may do once it's pinned.
  defp change(memo_id) do
    DB.update!(Memo, memo_id, pinned: false)

    "applied"
  end

  # Capped, so a test that never lets it go doesn't keep it running for good.
  defp holding(command_pid, fun) do
    fn ->
      :yes = :global.register_name({__MODULE__, :held}, self())
      send(command_pid, :held)

      receive do
        {:go, release_pid} -> send(release_pid, {:held_result, fun.(), command_pid})
      after
        @hold_cap -> :ok
      end
    end
  end

  defp memo do
    Memo
    |> one()
    |> trust()
    |> DB.read()
  end

  defp read(memo_id) do
    Memo
    |> DB.read(memo_id)
    |> visibility()
  end

  defp refusing(fun) do
    fun.()
  rescue
    MisuseError -> "refused"
  end

  defp sign_in(server, email, result) do
    user =
      User
      |> filter(email: ^email)
      |> one()
      |> trust()
      |> DB.read()

    put_action(%{server | user_id: user.id}, :show_result, result: result)
  end

  defp user_name(user_id) do
    User
    |> filter(id: ^user_id)
    |> one()
    |> trust()
    |> DB.read()
    |> Map.fetch!(:email)
    |> String.split("@")
    |> hd()
  end

  defp visibility(nil), do: "hidden"

  defp visibility(_memo), do: "visible"
end
