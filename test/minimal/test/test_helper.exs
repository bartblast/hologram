ExUnit.start()

# After ExUnit.start, so the env is recognized as test even when MIX_ENV is unset.
Hologram.Test.setup()
