# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :phoenix, :json_library, Jason

# Configures the endpoint
config :phoenix_demo, PhoenixDemoWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "hCcjh22viE2CoM6q/13ZLiA3nFDNecVkrnnOCmsfmoHTmK57GgSC2k8j9H8KAmhC",
  render_errors: [view: PhoenixDemoWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: PhoenixDemo.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $metadata $message\n",
  metadata: [:user_id, :periodic_job]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
