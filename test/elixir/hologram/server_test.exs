defmodule Hologram.ServerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Server

  alias Hologram.Component.Action
  alias Hologram.Runtime.Cookie
  alias Hologram.Server
  alias Hologram.Server.Metadata

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

  describe "from/1" do
    setup do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{"role" => "admin", "user_id" => 123})

      [conn: conn]
    end

    test "creates Server struct from Plug.Conn struct", %{conn: initial_conn} do
      conn =
        initial_conn
        |> Map.put(:cookies, %{"theme" => "dark", "username" => "abc123"})
        |> Map.put(:req_cookies, %{"theme" => "dark", "username" => "abc123"})

      result = from(conn)

      assert result == %Server{
               cookies: %{"theme" => "dark", "username" => "abc123"},
               session: %{"role" => "admin", "user_id" => 123}
             }
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
end
