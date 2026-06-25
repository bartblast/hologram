defmodule Hologram.Server.Helpers do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import Hologram.Server,
        only: [
          append_response_header: 3,
          delete_cookie: 2,
          delete_response_header: 2,
          delete_session: 2,
          delete_stash: 2,
          delete_user_id: 1,
          get_cookie: 2,
          get_cookie: 3,
          get_request_header: 2,
          get_request_header: 3,
          get_response_header: 2,
          get_response_header: 3,
          get_session: 2,
          get_session: 3,
          get_stash: 2,
          get_stash: 3,
          put_cookie: 3,
          put_cookie: 4,
          put_redirect: 2,
          put_redirect: 3,
          put_response_body: 2,
          put_response_header: 3,
          put_session: 3,
          put_stash: 3,
          put_status: 2,
          put_user_id: 2,
          referrer: 1,
          request_url: 1
        ]
    end
  end
end
