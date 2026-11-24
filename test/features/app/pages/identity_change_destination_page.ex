defmodule HologramFeatureTests.IdentityChangeDestinationPage do
  use Hologram.Page

  route "/identity-change-destination"

  layout HologramFeatureTests.Components.DefaultLayout

  # A test arms this script through `sessionStorage` and reloads the page with its bundle held
  # back. The driver waits for that held bundle before it runs another command, so the script is
  # what presses Back: once the runtime has taken Back and Forward over from the document's inline
  # listener and its socket is open, and before the page mounts. Before the socket opens, the tab
  # can't ask for the page's digest and reloads the entry instead. The script also records every
  # time the page Back restores shows anyone but the user, or rows other than theirs, since the
  # driver looks only once it's all over.
  def template do
    ~HOLO"""
    <p id="destination_title">Identity change destination</p>
    <script>
      {%raw}
        (() => {
          const armed = sessionStorage.getItem("hologram_back_before_mount");

          if (armed === null) {
            return;
          }

          sessionStorage.removeItem("hologram_back_before_mount");

          const [email, memos] = JSON.parse(armed);
          globalThis.__otherRows = [];

          const check = () => {
            const shownEmail = document.querySelector("#session_user")?.textContent.trim();
            const shownMemos = document.querySelector("#memos")?.textContent.trim();

            if ((shownEmail ?? email) !== email || (shownMemos ?? memos) !== memos) {
              globalThis.__otherRows.push([shownEmail, shownMemos]);
            }
          };

          new MutationObserver(check).observe(document.documentElement, {
            characterData: true,
            childList: true,
            subtree: true,
          });

          const pressBack = setInterval(() => {
            const shim = globalThis.Hologram;

            const ready =
              shim && !("_popstateShim" in shim) && !shim._missedPopstate && shim["wsConnected?"] === true;

            if (ready) {
              clearInterval(pressBack);
              globalThis.__mountedBeforeBack = (shim.mountedPage ?? null) !== null;
              history.back();
            }
          }, 5);
        })();
      {/raw}
    </script>
    """
  end
end
