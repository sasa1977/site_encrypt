use Mix.Config

config :phoenix, json_library: Jason
config :phoenix_demo, PhoenixDemo.Endpoint, []

if Mix.env() == :test do
  config :logger, level: :warn
end
