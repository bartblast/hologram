defmodule Reflex.Repo do
  use Ecto.Repo,
    otp_app: :reflex,
    adapter: Ecto.Adapters.Postgres
end
