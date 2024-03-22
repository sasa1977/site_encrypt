use Mix.Config

config :phoenix, json_library: Jason
config :phoenix_demo, PhoenixDemo.Endpoint, adapter: Bandit.PhoenixAdapter

if Mix.env() == :test do
  config :logger, level: :warn
end
