defmodule Hologram.Runtime.RouterTest do
  # use Hologram.Test.BasicCase, async: true
  # import Hologram.Router

  # alias Hologram.Router.SearchTree
  # alias Hologram.Test.Fixtures.Runtime.Router.Module1

  # setup do
  #   persistent_term_key = random_atom()
  #   init(persistent_term_key)

  #   [persistent_term_key: persistent_term_key]
  # end

  # describe "call/2" do
  #   test "request path is matched", opts do
  #     conn = Plug.Test.conn(:get, "/hologram-test-fixtures-runtime-router-module1")

  #     assert call(conn, opts) == %{
  #              conn
  #              | halted: true,
  #                resp_body: "page Hologram.Test.Fixtures.Runtime.Router.Module1 template",
  #                resp_headers: [
  #                  {"content-type", "text/html; charset=utf-8"},
  #                  {"cache-control", "max-age=0, private, must-revalidate"}
  #                ],
  #                state: :sent,
  #                status: 200
  #            }
  #   end

  #   test "request path is not matched", opts do
  #     conn = Plug.Test.conn(:get, "/my-unmatched-request-path")

  #     assert call(conn, opts) == %{
  #              conn
  #              | halted: false,
  #                resp_body: nil,
  #                resp_headers: [{"cache-control", "max-age=0, private, must-revalidate"}],
  #                state: :unset,
  #                status: nil
  #            }
  #   end
  # end

  # test "init/1" do
  #   persistent_term_key = random_atom()

  #   assert {:ok, nil} = init(persistent_term_key)

  #   search_tree = :persistent_term.get(persistent_term_key)

  #   assert %SearchTree.Node{
  #            value: nil,
  #            children: %{
  #              "hologram-test-fixtures-runtime-router-module1" => %SearchTree.Node{
  #                value: Module1,
  #                children: %{}
  #              }
  #            }
  #          } = search_tree
  # end

  # describe "resolve_page/2" do
  #   test "there is a matching route", %{persistent_term_key: persistent_term_key} do
  #     request_path = "/hologram-test-fixtures-runtime-router-module1"
  #     assert resolve_page(request_path, persistent_term_key) == Module1
  #   end

  #   test "there is no matching route", %{persistent_term_key: persistent_term_key} do
  #     request_path = "/unknown-path"
  #     refute resolve_page(request_path, persistent_term_key)
  #   end
  # end

  # test "start_link/1" do
  #   assert {:ok, pid} = start_link(@opts)
  #   assert is_pid(pid)
  #   # assert ets_table_exists?(@table_name)
  # end
end
