defmodule Hologram do
  @moduledoc ~S'''

  Hologram is a full stack isomorphic Elixir web framework that can be used on top of Phoenix.

  ## Inspired by

  Hologram was inspired by Elm, Phoenix LiveView, Surface, Svelte, Vue.js, Mint, Ruby on Rails.

  ## How it works

  The Hologram concept is that your web app is composed from the basic Hologram blocks of Layouts, Pages and Components.

  Hologram builds a call graph from the content of your Pages (which must follow some basic conventions) and determines what code is to be used on the client and what code is to be used on the server. Hologram then transpiles the code to be used on the client to JavaScript.

  Because the state is kept on the client, the programming model is simpler and thanks to stateless or stateful components the app is easily scalable.

  Code that is to be run on the client is encapsulated in “actions”, and code that is to be run on the server is encapsulated in “commands”.
  Actions can trigger commands, commands can trigger actions. Both actions and commands can be triggered directly by DOM events.

  The Client communicates with the Server using websockets. There is no boilerplate code required, Hologram automatically works out what is required.

  ## I want to see some code!

  To see how Hologram app is structured, and see some actual code, take a look at the Hologram’s test app: [hologram/test/e2e](https://github.com/bartblast/hologram/tree/master/test/e2e)

  ## Basic example
      defmodule MyPage do
      use Hologram.Page

      route "/my-page-path"

      def init(_params, _conn) do
        %{
          count: 0
        }
      end

      def template do
        ~H"""
        <div>Count is {@count}</div>
        <button on:click={:increment, by: 3}>Increment by</button>
        <Link to={MyOtherPage}>Go to other page</Link>
        """
      end

      def action(:increment, params, state) do
        put(state, :count, state.count + params.by)
      end

      def command(:save_to_db, _params) do
        # Repo.update (…)
        :counter_saved
      end
    end

  ## Is it used in production?

  Yes, it's used in Segmetric: https://www.segmetric.com/. Take a look at the “join beta” and “contact pages" which showcase form handling, or check the mobile menu.
  This all works on transpiled Elixir code! (But please, submit the forms only if you actually want to join the Segmetric beta or contact Segmetric - it is a live page, thanks!)

  ## Selling Points
  * State on the client - and all of the problems that get solved by this approach (below)…

  * No latency issues as most of the code is run immediately on the client. This makes it possible to create rich UI or even games.
  At the moment with LiveView you need something like fly.io to make it bearable, but you still have latency and can’t guarantee
  the response time (there is always some variance). And you still need some JS or Alpine to make it work. Until someone manages
  to create quantum internet (e.g. by taking advantage of entanglement), there are no workarounds for this problem.
  Not sure if this is even technically possible, though :wink:

  * Better offline support (internet connection loss, poor signal, etc.). Since most of the code is run on the client and you only hit the server to run some command from time to time,
  Hologram can work offline most of the time. This would also make it possible to create PWA’s or mobile apps through WebView, assuming you use something like LocalStorage.

  * Less server RAM used - state is kept in the browser instead of the socket.

  * Less CPU used - most of the code is run by the browser not by the server.

  * Less bandwidth used - only commands need to communicate with the server, no need to send diffs to rerender components.

  * No state sync problems - state is kept only in one place (browser) and the websocket communication used is stateless.

  * No JS or Alpine.js needed except for communication with some third party scripts or widgets,
  but this can also be solved by creating some standardized libs for popular packages that would handle the interop.

  * Very friendly to new Elixir converts or beginner devs. I want it to be very, very intuitive, so that you can focus on working on new features in your project instead
  of solving technical problems and writing boilerplate code.

  ## Roadmap

  This is work in progress (although usable and used in production). To check what works and what is planned - take a look at the roadmap in the readme at: [Github bartblast/hologram](https://github.com/bartblast/hologram#readme)

  To meet the objective of being a very friendly developer experience, Hologram will provide out of the box such things as UI component library (CSS framework agnostic),
  authentication, authorization, easy debugging (with time travel), caching, localization and some other features that you typically use in a web app.

  I believe that using Hologram’s approach, i.e. Elixir-JS transpilation, code on client and action/command architecture it will be possible to create something as productive as Rails,
  without its shortcomings related to scalability, efficiency, etc.

  ## History / background

  I tried to write this kind of framework first in Ruby, and actually managed to create a working prototype, but the performance was not satisfactory.
  Then I tried Crystal, but it was very hard to work with its AST. Then I moved to Kotlin, but I realised that it’s better to use a dynamically typed language …
  Then I found Elixir in 2018 and fell in love with it. I started work on Hologram in the summer of 2020.

  '''
end
