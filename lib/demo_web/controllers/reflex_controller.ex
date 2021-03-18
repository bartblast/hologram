defmodule DemoWeb.HolofografController do
  use DemoWeb, :controller

  def index(conn, _params) do
    json(conn, :ok)
  end
end
