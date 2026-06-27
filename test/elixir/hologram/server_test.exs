defmodule Hologram.ServerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Server

  alias Hologram.Component.Action
  alias Hologram.Runtime.Cookie
  alias Hologram.Server
  alias Hologram.Server.Metadata
  alias Hologram.Test.Fixtures.Router.Helpers.Module1
  alias Hologram.Test.Fixtures.Router.Helpers.Module2

  describe "append_response_header/3" do
    test "appends a value to an existing response header" do
      server = %Server{response_headers: %{"vary" => "Accept"}}
      result = append_response_header(server, "vary", "Accept-Encoding")

      assert result.response_headers == %{"vary" => "Accept, Accept-Encoding"}
    end

    test "sets the header when it is not present" do
      result = append_response_header(%Server{}, "vary", "Accept")

      assert result.response_headers == %{"vary" => "Accept"}
    end

    test "downcases the header name" do
      server = %Server{response_headers: %{"vary" => "Accept"}}
      result = append_response_header(server, "Vary", "Accept-Encoding")

      assert result.response_headers == %{"vary" => "Accept, Accept-Encoding"}
    end

    test "raises ArgumentError when the name is not a string" do
      assert_error ArgumentError,
                   "Response header name and value must be strings, but received 123 and \"Accept\"",
                   fn ->
                     append_response_header(%Server{}, 123, "Accept")
                   end
    end

    test "raises ArgumentError when the value is not a string" do
      assert_error ArgumentError,
                   "Response header name and value must be strings, but received \"vary\" and 123",
                   fn ->
                     append_response_header(%Server{}, "vary", 123)
                   end
    end

    test "raises ArgumentError for a cookie header" do
      assert_error ArgumentError,
                   "set-cookie is managed by the cookie functions (put_cookie, get_cookie, delete_cookie), not the header helpers",
                   fn ->
                     append_response_header(%Server{}, "set-cookie", "id=1")
                   end
    end
  end

  describe "delete_cookie/2" do
    test "removes an existing cookie from the server struct" do
      server = %Server{cookies: %{"theme" => "dark", "user_id" => 123}}

      result = delete_cookie(server, "user_id")

      assert result.cookies == %{"theme" => "dark"}
      assert result.__meta__.cookie_ops["user_id"] == :delete
    end

    test "handles deleting a nonexistent cookie as no-op" do
      server = %Server{cookies: %{"theme" => "dark"}}

      result = delete_cookie(server, "nonexistent")

      assert result == server
    end

    test "handles deleting from empty cookies as no-op" do
      server = %Server{cookies: %{}}

      result = delete_cookie(server, "any_key")

      assert result == server
    end

    test "preserves existing metadata cookie_ops when deleting" do
      server = %Server{
        cookies: %{"existing" => "some_value", "theme" => "dark", "user_id" => 123},
        __meta__: %Metadata{
          cookie_ops: %{
            "existing" => %Cookie{value: "some_value"}
          }
        }
      }

      result = delete_cookie(server, "user_id")

      assert result.cookies == %{"existing" => "some_value", "theme" => "dark"}
      assert result.__meta__.cookie_ops["existing"] == %Cookie{value: "some_value"}
      assert result.__meta__.cookie_ops["user_id"] == :delete
    end

    test "preserves existing metadata when deleting nonexistent cookie" do
      server = %Server{
        cookies: %{"existing" => "some_value", "theme" => "dark"},
        __meta__: %Metadata{
          cookie_ops: %{
            "existing" => %Cookie{value: "some_value"}
          }
        }
      }

      result = delete_cookie(server, "nonexistent")

      assert result == server
    end

    test "overwrites existing cookie operation when same key is deleted" do
      server = %Server{
        cookies: %{"user_id" => 123},
        __meta__: %Metadata{
          cookie_ops: %{
            "user_id" => %Cookie{value: 123}
          }
        }
      }

      result = delete_cookie(server, "user_id")

      assert result.cookies == %{}
      assert result.__meta__.cookie_ops["user_id"] == :delete
    end

    test "preserves other server struct fields unchanged" do
      server = %Server{
        cookies: %{"user_id" => 123},
        next_action: %Action{name: :some_action}
      }

      result = delete_cookie(server, "user_id")

      assert result.next_action == %Action{name: :some_action}
    end
  end

  describe "delete_response_header/2" do
    test "removes an existing response header" do
      server = %Server{response_headers: %{"cache-control" => "no-store", "x-custom" => "1"}}
      result = delete_response_header(server, "x-custom")

      assert result.response_headers == %{"cache-control" => "no-store"}
    end

    test "downcases the name before removing" do
      server = %Server{response_headers: %{"x-custom" => "1"}}
      result = delete_response_header(server, "X-Custom")

      assert result.response_headers == %{}
    end

    test "handles removing a nonexistent header as no-op" do
      server = %Server{response_headers: %{"x-custom" => "1"}}
      result = delete_response_header(server, "nonexistent")

      assert result == server
    end

    test "raises ArgumentError when name is not a string" do
      assert_error ArgumentError,
                   "Response header name must be a string, but received 123",
                   fn ->
                     delete_response_header(%Server{}, 123)
                   end
    end

    test "raises ArgumentError for a cookie header" do
      assert_error ArgumentError,
                   "set-cookie is managed by the cookie functions (put_cookie, get_cookie, delete_cookie), not the header helpers",
                   fn ->
                     delete_response_header(%Server{}, "set-cookie")
                   end
    end
  end

  describe "delete_session/2" do
    test "removes an existing session entry from the server struct using atom key" do
      server = %Server{session: %{"theme" => "dark", "user_id" => 123}}

      result = delete_session(server, :user_id)

      assert result.session == %{"theme" => "dark"}
      assert result.__meta__.session_ops["user_id"] == :delete
    end

    test "removes an existing session entry from the server struct using string key" do
      server = %Server{session: %{"theme" => "dark", "user_id" => 123}}

      result = delete_session(server, "user_id")

      assert result.session == %{"theme" => "dark"}
      assert result.__meta__.session_ops["user_id"] == :delete
    end

    test "handles deleting a nonexistent session entry as no-op" do
      server = %Server{session: %{"theme" => "dark"}}

      result = delete_session(server, "nonexistent")

      assert result == server
    end

    test "handles deleting from empty session as no-op" do
      server = %Server{session: %{}}

      result = delete_session(server, "any_key")

      assert result == server
    end

    test "preserves existing metadata session_ops when deleting" do
      server = %Server{
        session: %{"existing" => "some_value", "theme" => "dark", "user_id" => 123},
        __meta__: %Metadata{
          session_ops: %{
            "existing" => {:put, "some_value"}
          }
        }
      }

      result = delete_session(server, "user_id")

      assert result.session == %{"existing" => "some_value", "theme" => "dark"}
      assert result.__meta__.session_ops["existing"] == {:put, "some_value"}
      assert result.__meta__.session_ops["user_id"] == :delete
    end

    test "preserves existing metadata when deleting nonexistent session entry" do
      server = %Server{
        session: %{"existing" => "some_value", "theme" => "dark"},
        __meta__: %Metadata{
          session_ops: %{
            "existing" => {:put, "some_value"}
          }
        }
      }

      result = delete_session(server, "nonexistent")

      assert result == server
    end

    test "overwrites existing session operation when same key is deleted" do
      server = %Server{
        session: %{"user_id" => 123},
        __meta__: %Metadata{
          cookie_ops: %{
            "user_id" => {:put, 123}
          }
        }
      }

      result = delete_session(server, "user_id")

      assert result.session == %{}
      assert result.__meta__.session_ops["user_id"] == :delete
    end

    test "preserves other server struct fields unchanged" do
      server = %Server{
        session: %{"user_id" => 123},
        next_action: %Action{name: :some_action}
      }

      result = delete_session(server, "user_id")

      assert result.next_action == %Action{name: :some_action}
    end
  end

  describe "delete_stash/2" do
    test "removes a key from the stash" do
      server = %Server{stash: %{current_user: 123, locale: "en"}}
      result = delete_stash(server, :current_user)

      assert result.stash == %{locale: "en"}
    end

    test "handles deleting a missing key as a no-op" do
      server = %Server{stash: %{locale: "en"}}
      result = delete_stash(server, :current_user)

      assert result.stash == %{locale: "en"}
    end

    test "raises ArgumentError when the key is not an atom" do
      assert_error ArgumentError,
                   "Stash key must be an atom, but received \"current_user\"",
                   fn ->
                     delete_stash(%Server{}, "current_user")
                   end
    end
  end

  describe "delete_user_id/1" do
    test "clears the user identity" do
      result = delete_user_id(%Server{user_id: 123})

      assert result.user_id == nil
    end
  end

  describe "from/1" do
    setup do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{"role" => "admin", "user_id" => 123})

      [conn: conn]
    end

    test "populates cookies from the conn", %{conn: initial_conn} do
      conn =
        initial_conn
        |> Map.put(:cookies, %{"theme" => "dark", "username" => "abc123"})
        |> Map.put(:req_cookies, %{"theme" => "dark", "username" => "abc123"})

      result = from(conn)

      assert result.cookies == %{"theme" => "dark", "username" => "abc123"}
    end

    test "excludes hologram_session cookie from server cookies", %{conn: initial_conn} do
      conn =
        initial_conn
        |> Map.put(:cookies, %{
          "user_id" => "abc123",
          "theme" => "dark",
          "hologram_session" => "session_data_xyz789"
        })
        |> Map.put(:req_cookies, %{
          "user_id" => "abc123",
          "theme" => "dark",
          "hologram_session" => "session_data_xyz789"
        })

      result = from(conn)

      refute Map.has_key?(result.cookies, "hologram_session")
    end

    test "populates session_id from the Hologram session entry", %{conn: initial_conn} do
      conn =
        initial_conn
        |> Plug.Test.init_test_session(%{hologram_session_id: "some-session-id"})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})

      assert from(conn).session_id == "some-session-id"
    end

    test "leaves session_id nil when no Hologram session entry is present", %{conn: initial_conn} do
      conn =
        initial_conn
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})

      assert from(conn).session_id == nil
    end

    test "populates user_id from the Hologram session entry", %{conn: initial_conn} do
      conn =
        initial_conn
        |> Plug.Test.init_test_session(%{hologram_user_id: 42})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})

      assert from(conn).user_id == 42
    end

    test "leaves user_id nil when no Hologram user entry is present", %{conn: initial_conn} do
      conn =
        initial_conn
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})

      assert from(conn).user_id == nil
    end

    test "strips Hologram-managed keys from the session map" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{
          :hologram_session_id => "some-session-id",
          :hologram_user_id => 42,
          "role" => "admin"
        })
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})

      assert from(conn).session == %{"role" => "admin"}
    end

    test "populates request fields from the conn" do
      conn =
        :post
        |> Plug.Test.conn("/admin/users?page=2&sort=desc")
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})

      result = from(conn)

      assert result.host == "www.example.com"
      assert result.ip == "127.0.0.1"
      assert result.method == :post
      assert result.path == "/admin/users"
      assert result.port == 80
      assert result.query == %{"page" => "2", "sort" => "desc"}
      assert result.raw_query == "page=2&sort=desc"
      assert result.scheme == :http
    end

    test "falls back to :unknown for a non-standard request method" do
      conn =
        %{Plug.Test.conn(:get, "/") | method: "PROPFIND"}
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})

      assert from(conn).method == :unknown
    end

    test "comma-joins a multi-value request header" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})
        |> Map.put(:req_headers, [
          {"accept", "text/html"},
          {"accept", "application/json"}
        ])

      assert from(conn).request_headers == %{"accept" => "text/html, application/json"}
    end

    test "drops the cookie request header" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:cookies, %{})
        |> Map.put(:req_cookies, %{})
        |> Map.put(:req_headers, [
          {"cookie", "theme=dark"},
          {"user-agent", "test-agent"}
        ])

      assert from(conn).request_headers == %{"user-agent" => "test-agent"}
    end
  end

  describe "get_cookie/2" do
    test "returns the value of an existing cookie" do
      server = %Server{cookies: %{"user_id" => "abc123", "theme" => "dark"}}

      result = get_cookie(server, "user_id")

      assert result == "abc123"
    end

    test "returns nil for a nonexistent cookie" do
      server = %Server{cookies: %{"user_id" => "abc123"}}

      result = get_cookie(server, "nonexistent")

      assert result == nil
    end

    test "returns nil when cookies are empty" do
      server = %Server{cookies: %{}}

      result = get_cookie(server, "any_key")

      assert result == nil
    end
  end

  describe "get_cookie/3" do
    test "returns custom default for a nonexistent cookie" do
      server = %Server{cookies: %{"user_id" => "abc123"}}

      result = get_cookie(server, "nonexistent", "default_value")

      assert result == "default_value"
    end

    test "returns custom default when cookies are empty" do
      server = %Server{cookies: %{}}

      result = get_cookie(server, "any_key", "fallback")

      assert result == "fallback"
    end

    test "returns actual value over default when cookie exists" do
      server = %Server{cookies: %{"theme" => "dark"}}

      result = get_cookie(server, "theme", "light")

      assert result == "dark"
    end
  end

  describe "get_cookie_ops/1" do
    test "returns cookie operations recorded in the server struct's metadata" do
      server = %Server{cookies: %{"existing_cookie" => "value"}}

      new_server =
        server
        |> put_cookie("new_cookie", "new_value")
        |> delete_cookie("existing_cookie")

      result = get_cookie_ops(new_server)

      assert result == %{
               "new_cookie" => %Cookie{value: "new_value"},
               "existing_cookie" => :delete
             }
    end
  end

  describe "get_request_header/2 & get_request_header/3" do
    test "returns the value of a present header" do
      server = %Server{request_headers: %{"accept-language" => "en-US"}}

      assert get_request_header(server, "accept-language") == "en-US"
    end

    test "downcases the lookup name" do
      server = %Server{request_headers: %{"accept-language" => "en-US"}}

      assert get_request_header(server, "Accept-Language") == "en-US"
    end

    test "returns nil when the header is not present" do
      assert get_request_header(%Server{}, "accept-language") == nil
    end

    test "returns the given default when the header is not present" do
      assert get_request_header(%Server{}, "accept-language", "default") == "default"
    end

    test "raises ArgumentError when the name is not a string" do
      assert_error ArgumentError,
                   "Request header name must be a string, but received 123",
                   fn ->
                     get_request_header(%Server{}, 123)
                   end
    end

    test "raises ArgumentError for a cookie header" do
      assert_error ArgumentError,
                   "cookie is managed by the cookie functions (put_cookie, get_cookie, delete_cookie), not the header helpers",
                   fn ->
                     get_request_header(%Server{}, "cookie")
                   end
    end
  end

  describe "get_response_header/2 & get_response_header/3" do
    test "returns the value of a present header" do
      server = %Server{response_headers: %{"cache-control" => "no-store"}}

      assert get_response_header(server, "cache-control") == "no-store"
    end

    test "downcases the lookup name" do
      server = %Server{response_headers: %{"cache-control" => "no-store"}}

      assert get_response_header(server, "Cache-Control") == "no-store"
    end

    test "returns nil when the header is not present" do
      assert get_response_header(%Server{}, "cache-control") == nil
    end

    test "returns the given default when the header is not present" do
      assert get_response_header(%Server{}, "cache-control", "default") == "default"
    end

    test "raises ArgumentError when the name is not a string" do
      assert_error ArgumentError,
                   "Response header name must be a string, but received 123",
                   fn ->
                     get_response_header(%Server{}, 123)
                   end
    end

    test "raises ArgumentError for a cookie header" do
      assert_error ArgumentError,
                   "set-cookie is managed by the cookie functions (put_cookie, get_cookie, delete_cookie), not the header helpers",
                   fn ->
                     get_response_header(%Server{}, "set-cookie")
                   end
    end
  end

  describe "get_session_ops/1" do
    test "returns session operations recorded in the server struct's metadata" do
      server = %Server{session: %{"existing_session_entry" => "value"}}

      new_server =
        server
        |> put_session("new_session_entry", "new_value")
        |> delete_session("existing_session_entry")

      result = get_session_ops(new_server)

      assert result == %{
               "new_session_entry" => {:put, "new_value"},
               "existing_session_entry" => :delete
             }
    end
  end

  describe "get_session/2" do
    test "returns the value for an existing session entry" do
      server = %Server{session: %{"theme" => "dark", "user_id" => 123}}

      result = get_session(server, "user_id")

      assert result == 123
    end

    test "returns nil for a nonexistent session entry" do
      server = %Server{session: %{"user_id" => 123}}

      result = get_session(server, "nonexistent")

      assert result == nil
    end

    test "returns nil when session is empty" do
      server = %Server{session: %{}}

      result = get_session(server, "any_key")

      assert result == nil
    end

    test "converts atom session key to string" do
      server = %Server{session: %{"theme" => "dark", "user_id" => 123}}

      result = get_session(server, :user_id)

      assert result == 123
    end
  end

  describe "get_session/3" do
    test "returns custom default for a nonexistent session entry" do
      server = %Server{session: %{"user_id" => 123}}

      result = get_session(server, "nonexistent", "default_value")

      assert result == "default_value"
    end

    test "returns custom default when session is empty" do
      server = %Server{session: %{}}

      result = get_session(server, "any_key", "fallback")

      assert result == "fallback"
    end

    test "returns actual value over default when session entry exists" do
      server = %Server{session: %{"theme" => "dark"}}

      result = get_session(server, "theme", "light")

      assert result == "dark"
    end

    test "converts atom session key to string" do
      server = %Server{session: %{"theme" => "dark", "user_id" => 123}}

      result = get_session(server, :user_id, 987)

      assert result == 123
    end
  end

  describe "get_stash/2 & get_stash/3" do
    test "returns the value for an existing key" do
      server = %Server{stash: %{current_user: 123}}

      assert get_stash(server, :current_user) == 123
    end

    test "returns nil for a missing key" do
      assert get_stash(%Server{}, :current_user) == nil
    end

    test "returns the default for a missing key" do
      assert get_stash(%Server{}, :current_user, :guest) == :guest
    end

    test "raises ArgumentError when the key is not an atom" do
      assert_error ArgumentError,
                   "Stash key must be an atom, but received \"current_user\"",
                   fn ->
                     get_stash(%Server{}, "current_user")
                   end
    end
  end

  describe "has_cookie_ops?/1" do
    test "returns false when no cookie operations have been recorded" do
      server = %Server{cookies: %{"user_id" => "123"}}

      result = has_cookie_ops?(server)

      assert result == false
    end

    test "returns true when put operation has been recorded" do
      server = put_cookie(%Server{}, "theme", "dark")

      result = has_cookie_ops?(server)

      assert result == true
    end

    test "returns true when delete operation has been recorded" do
      server = %Server{cookies: %{"theme" => "dark"}}
      new_server = delete_cookie(server, "theme")

      result = has_cookie_ops?(new_server)

      assert result == true
    end

    test "returns true when multiple operations have been recorded" do
      server = %Server{cookies: %{"user_id" => "123", "theme" => "dark"}}

      new_server =
        server
        |> put_cookie("lang", "en")
        |> delete_cookie("user_id")

      result = has_cookie_ops?(new_server)

      assert result == true
    end
  end

  describe "put_cookie/3 & put_cookie/4" do
    test "adds a cookie with default options" do
      result = put_cookie(%Server{}, "my_cookie", "abc123")

      expected_cookie = %Cookie{
        value: "abc123",
        domain: nil,
        http_only: true,
        max_age: nil,
        path: nil,
        same_site: :lax,
        secure: true
      }

      assert result.cookies["my_cookie"] == "abc123"
      assert result.__meta__.cookie_ops["my_cookie"] == expected_cookie
    end

    test "adds a cookie with custom options" do
      opts = [
        domain: "example.com",
        http_only: false,
        max_age: 3_600,
        path: "/app",
        same_site: :strict,
        secure: false
      ]

      result = put_cookie(%Server{}, "my_cookie", "abc123", opts)

      expected_cookie = %Cookie{
        value: "abc123",
        domain: "example.com",
        http_only: false,
        max_age: 3_600,
        path: "/app",
        same_site: :strict,
        secure: false
      }

      assert result.cookies["my_cookie"] == "abc123"
      assert result.__meta__.cookie_ops["my_cookie"] == expected_cookie
    end

    test "adds multiple cookies to existing server struct" do
      server = %Server{cookies: %{"existing" => "old"}}

      result =
        server
        |> put_cookie("first", "value_1")
        |> put_cookie("second", "value_2")

      assert result == %Server{
               cookies: %{
                 "existing" => "old",
                 "first" => "value_1",
                 "second" => "value_2"
               },
               __meta__: %Metadata{
                 cookie_ops: %{
                   "first" => %Cookie{value: "value_1"},
                   "second" => %Cookie{value: "value_2"}
                 }
               }
             }
    end

    test "overwrites existing cookie with same key" do
      server = %Server{
        cookies: %{"theme" => "light"},
        __meta__: %Metadata{
          cookie_ops: %{
            "theme" => %Cookie{value: "light"}
          }
        }
      }

      result = put_cookie(server, "theme", "dark")

      assert result == %Server{
               cookies: %{"theme" => "dark"},
               __meta__: %Metadata{
                 cookie_ops: %{
                   "theme" => %Cookie{value: "dark"}
                 }
               }
             }
    end

    test "supports different value types" do
      result =
        %Server{}
        |> put_cookie("atom", :abc)
        |> put_cookie("string", "text")
        |> put_cookie("integer", 42)
        |> put_cookie("list", [1, 2, 3])

      cookies = result.cookies
      assert cookies["atom"] == :abc
      assert cookies["string"] == "text"
      assert cookies["integer"] == 42
      assert cookies["list"] == [1, 2, 3]

      cookie_ops = result.__meta__.cookie_ops
      assert cookie_ops["atom"] == %Cookie{value: :abc}
      assert cookie_ops["string"] == %Cookie{value: "text"}
      assert cookie_ops["integer"] == %Cookie{value: 42}
      assert cookie_ops["list"] == %Cookie{value: [1, 2, 3]}
    end

    test "raises ArgumentError when key is not a string" do
      expected_msg = """
      Cookie key must be a string, but received :abc.

      Cookie keys must be strings according to web standards.
      Try converting your key to a string: "abc".\
      """

      assert_error ArgumentError, expected_msg, fn ->
        put_cookie(%Server{}, :abc, "value")
      end
    end

    test "raises KeyError when invalid option is given" do
      assert_error KeyError, "key :invalid_opt not found", fn ->
        put_cookie(%Server{}, "abc", :value, invalid_opt: 123)
      end
    end

    test "partial options override defaults" do
      result = put_cookie(%Server{}, "my_cookie", "abc123", secure: false, path: "/app")

      expected_cookie = %Cookie{
        value: "abc123",
        domain: nil,
        http_only: true,
        max_age: nil,
        path: "/app",
        same_site: :lax,
        secure: false
      }

      assert result.cookies == %{"my_cookie" => "abc123"}
      assert result.__meta__.cookie_ops["my_cookie"] == expected_cookie
    end
  end

  describe "put_redirect/2 & put_redirect/3" do
    test "redirects to a URL string" do
      result = put_redirect(%Server{}, "https://example.com/next")

      assert result.status == 302
      assert result.response_headers == %{"location" => "https://example.com/next"}
    end

    test "redirects to a page module" do
      result = put_redirect(%Server{}, Module1)

      assert result.status == 302

      assert result.response_headers == %{
               "location" => "/hologram-test-fixtures-router-helpers-module1"
             }
    end

    test "redirects to a page module with params" do
      result = put_redirect(%Server{}, Module2, param_1: :foo, param_2: 42)

      assert result.status == 302

      assert result.response_headers == %{
               "location" => "/hologram-test-fixtures-router-helpers-module2/foo/42"
             }
    end

    test "supports other status codes by following with put_status/2" do
      result =
        %Server{}
        |> put_redirect("https://example.com/next")
        |> put_status(301)

      assert result.status == 301
      assert result.response_headers == %{"location" => "https://example.com/next"}
    end

    test "raises ArgumentError when the target is neither a URL string nor a page module" do
      assert_error ArgumentError,
                   "Redirect target must be a URL string or a page module, but received 123",
                   fn ->
                     put_redirect(%Server{}, 123)
                   end
    end

    test "raises ArgumentError when params are given with a URL string" do
      assert_error ArgumentError,
                   "Redirect params are only supported with a page module, but received \"https://example.com\"",
                   fn ->
                     put_redirect(%Server{}, "https://example.com", foo: 1)
                   end
    end
  end

  describe "put_response_body/2" do
    test "accepts a binary response body" do
      result = put_response_body(%Server{}, "Too Many Requests")

      assert result.response_body == "Too Many Requests"
    end

    test "accepts an iolist response body" do
      result = put_response_body(%Server{}, ["Too ", "Many ", "Requests"])

      assert result.response_body == ["Too ", "Many ", "Requests"]
    end

    test "raises ArgumentError when the response body is not iodata" do
      assert_error ArgumentError,
                   "Response body must be iodata (a binary or an iolist), but received %{error: \"nope\"}",
                   fn ->
                     put_response_body(%Server{}, %{error: "nope"})
                   end
    end
  end

  describe "put_response_header/3" do
    test "adds a response header" do
      result = put_response_header(%Server{}, "cache-control", "no-store")

      assert result.response_headers == %{"cache-control" => "no-store"}
    end

    test "downcases the header name" do
      result = put_response_header(%Server{}, "Cache-Control", "no-store")

      assert result.response_headers == %{"cache-control" => "no-store"}
    end

    test "overwrites an existing header regardless of case" do
      server = %Server{response_headers: %{"cache-control" => "no-store"}}
      result = put_response_header(server, "Cache-Control", "max-age=60")

      assert result.response_headers == %{"cache-control" => "max-age=60"}
    end

    test "raises ArgumentError when the name is not a string" do
      assert_error ArgumentError,
                   "Response header name and value must be strings, but received 123 and \"no-store\"",
                   fn ->
                     put_response_header(%Server{}, 123, "no-store")
                   end
    end

    test "raises ArgumentError when the value is not a string" do
      assert_error ArgumentError,
                   "Response header name and value must be strings, but received \"x-custom\" and 123",
                   fn ->
                     put_response_header(%Server{}, "x-custom", 123)
                   end
    end

    test "raises ArgumentError for a cookie header" do
      assert_error ArgumentError,
                   "set-cookie is managed by the cookie functions (put_cookie, get_cookie, delete_cookie), not the header helpers",
                   fn ->
                     put_response_header(%Server{}, "set-cookie", "id=1")
                   end
    end
  end

  describe "put_session/3" do
    test "adds a session entry using atom key" do
      result = put_session(%Server{}, :username, "abc123")

      assert result.session["username"] == "abc123"
      assert result.__meta__.session_ops["username"] == {:put, "abc123"}
    end

    test "adds a session entry using string key" do
      result = put_session(%Server{}, "username", "abc123")

      assert result.session["username"] == "abc123"
      assert result.__meta__.session_ops["username"] == {:put, "abc123"}
    end

    test "adds multiple session entries to existing server struct" do
      server = %Server{session: %{"existing" => "old"}}

      result =
        server
        |> put_session("first", "value_1")
        |> put_session("second", "value_2")

      assert result == %Server{
               session: %{
                 "existing" => "old",
                 "first" => "value_1",
                 "second" => "value_2"
               },
               __meta__: %Metadata{
                 session_ops: %{
                   "first" => {:put, "value_1"},
                   "second" => {:put, "value_2"}
                 }
               }
             }
    end

    test "overwrites existing session entry with same key" do
      server = %Server{
        session: %{"theme" => "light"},
        __meta__: %Metadata{
          session_ops: %{
            "theme" => {:put, "light"}
          }
        }
      }

      result = put_session(server, "theme", "dark")

      assert result == %Server{
               session: %{"theme" => "dark"},
               __meta__: %Metadata{
                 session_ops: %{
                   "theme" => {:put, "dark"}
                 }
               }
             }
    end

    test "supports different value types" do
      result =
        %Server{}
        |> put_session("atom", :abc)
        |> put_session("string", "text")
        |> put_session("integer", 42)
        |> put_session("list", [1, 2, 3])

      session = result.session
      assert session["atom"] == :abc
      assert session["string"] == "text"
      assert session["integer"] == 42
      assert session["list"] == [1, 2, 3]

      session_ops = result.__meta__.session_ops
      assert session_ops["atom"] == {:put, :abc}
      assert session_ops["string"] == {:put, "text"}
      assert session_ops["integer"] == {:put, 42}
      assert session_ops["list"] == {:put, [1, 2, 3]}
    end

    test "raises ArgumentError when key is not an atom or a string" do
      assert_error ArgumentError,
                   "Session key must be an atom or a string, but received 123",
                   fn ->
                     put_session(%Server{}, 123, "value")
                   end
    end
  end

  describe "put_stash/3" do
    test "stores a value under an atom key" do
      result = put_stash(%Server{}, :current_user, 123)

      assert result.stash == %{current_user: 123}
    end

    test "overwrites an existing key" do
      server = %Server{stash: %{current_user: 123}}
      result = put_stash(server, :current_user, 456)

      assert result.stash == %{current_user: 456}
    end

    test "raises ArgumentError when the key is not an atom" do
      assert_error ArgumentError,
                   "Stash key must be an atom, but received \"current_user\"",
                   fn ->
                     put_stash(%Server{}, "current_user", 123)
                   end
    end
  end

  describe "put_status/2" do
    test "sets an integer status code" do
      result = put_status(%Server{}, 404)

      assert result.status == 404
    end

    test "resolves an atom alias to its numeric code" do
      result = put_status(%Server{}, :not_found)

      assert result.status == 404
    end

    test "overwrites an existing status" do
      result = put_status(%Server{status: 200}, 403)

      assert result.status == 403
    end

    test "raises ArgumentError for an unknown atom alias" do
      assert_error ArgumentError,
                   "Unknown status alias: :bogus",
                   fn ->
                     put_status(%Server{}, :bogus)
                   end
    end

    test "raises ArgumentError for an out-of-range status code" do
      assert_error ArgumentError,
                   "Response status must be an HTTP status code (100..599) or a status atom alias, but received 4040",
                   fn ->
                     put_status(%Server{}, 4040)
                   end
    end

    test "raises ArgumentError when status is not an integer or an atom" do
      assert_error ArgumentError,
                   "Response status must be an HTTP status code (100..599) or a status atom alias, but received \"404\"",
                   fn ->
                     put_status(%Server{}, "404")
                   end
    end
  end

  describe "put_user_id/2" do
    test "sets a string identity" do
      result = put_user_id(%Server{}, "user-123")

      assert result.user_id == "user-123"
    end

    test "sets an integer identity" do
      result = put_user_id(%Server{}, 123)

      assert result.user_id == 123
    end

    test "sets an atom identity" do
      result = put_user_id(%Server{}, :admin)

      assert result.user_id == :admin
    end

    test "overwrites an existing user identity" do
      result = put_user_id(%Server{user_id: 123}, 456)

      assert result.user_id == 456
    end

    test "raises ArgumentError when the identity is not a string, integer, or atom" do
      assert_error ArgumentError,
                   "User ID must be a string, integer, or atom, but received %{}",
                   fn ->
                     put_user_id(%Server{}, %{})
                   end
    end
  end

  describe "referrer_url/1" do
    test "returns the value of the referer header" do
      server = %Server{request_headers: %{"referer" => "https://example.com/from"}}

      assert referrer_url(server) == "https://example.com/from"
    end

    test "returns nil when the referer header is absent" do
      assert referrer_url(%Server{}) == nil
    end
  end

  describe "request_url/1" do
    test "assembles the full URL from the request fields" do
      server = %Server{
        scheme: :https,
        host: "example.com",
        port: 8443,
        path: "/admin/users",
        raw_query: "page=2&sort=desc"
      }

      assert request_url(server) == "https://example.com:8443/admin/users?page=2&sort=desc"
    end

    test "omits the default port for http" do
      server = %Server{scheme: :http, host: "example.com", port: 80, path: "/"}

      assert request_url(server) == "http://example.com/"
    end

    test "omits the default port for https" do
      server = %Server{scheme: :https, host: "example.com", port: 443, path: "/"}

      assert request_url(server) == "https://example.com/"
    end

    test "omits the query string when empty" do
      server = %Server{
        scheme: :https,
        host: "example.com",
        port: 443,
        path: "/about",
        raw_query: ""
      }

      assert request_url(server) == "https://example.com/about"
    end

    test "omits the query string when nil" do
      server = %Server{
        scheme: :https,
        host: "example.com",
        port: 443,
        path: "/about",
        raw_query: nil
      }

      assert request_url(server) == "https://example.com/about"
    end
  end
end
