defmodule SiteEncrypt.Certbot do
  @behaviour SiteEncrypt.Certifier.Job
  alias SiteEncrypt.Logger

  @impl SiteEncrypt.Certifier.Job
  def pems(config) do
    [
      privkey: keyfile(config),
      cert: certfile(config),
      chain: cacertfile(config)
    ]
    |> Stream.map(fn {type, path} ->
      case File.read(path) do
        {:ok, content} -> {type, content}
        _error -> nil
      end
    end)
    |> Enum.split_with(&is_nil/1)
    |> case do
      {[], pems} -> {:ok, pems}
      {[_ | _], _} -> :error
    end
  end

  @impl SiteEncrypt.Certifier.Job
  def certify(config, _http_pool, opts) do
    ensure_folders(config)
    original_keys_sha = keys_sha(config)

    result =
      if match?({:ok, _}, pems(config)), do: renew(config, opts), else: certonly(config, opts)

    case result do
      {output, 0} ->
        Logger.log(config.log_level, output)
        if keys_sha(config) != original_keys_sha, do: :new_cert, else: :no_change

      {output, _error} ->
        Logger.log(:error, output)
        :error
    end
  end

  @impl SiteEncrypt.Certifier.Job
  def full_challenge(config, challenge) do
    Path.join([
      webroot_folder(%{base_folder: config.base_folder}),
      ".well-known",
      "acme-challenge",
      challenge
    ])
    |> File.read!()
  end

  defp ensure_folders(config) do
    Enum.each(
      [config_folder(config), work_folder(config), webroot_folder(config)],
      &File.mkdir_p!/1
    )
  end

  defp certonly(config, opts) do
    certbot_cmd(
      config,
      opts,
      ~w(certonly -m #{config.email} --webroot --webroot-path #{webroot_folder(config)} --agree-tos) ++
        domain_params(config)
    )
  end

  defp renew(config, opts) do
    args =
      Enum.reduce(
        opts,
        ~w(-m #{config.email} --agree-tos --no-random-sleep-on-renew --cert-name #{config.domain}),
        &add_arg/2
      )

    certbot_cmd(config, opts, ["renew" | args])
  end

  defp add_arg({:force_renewal, true}, args), do: ["--force-renewal" | args]
  defp add_arg(_, args), do: args

  defp certbot_cmd(config, opts, args),
    do: System.cmd("certbot", args ++ common_args(config, opts), stderr_to_stdout: true)

  defp common_args(config, opts) do
    ~w(
      --server #{ca_url(config.ca_url)}
      --work-dir #{work_folder(config)}
      --config-dir #{config_folder(config)}
      --logs-dir #{log_folder(config)}
      --no-self-upgrade
      --non-interactive
      #{unless Keyword.get(opts, :verify_server_cert, true), do: "--no-verify-ssl"}
    )
  end

  defp ca_url({:local_acme_server, opts}),
    do: "https://localhost:#{Keyword.fetch!(opts, :port)}/directory"

  defp ca_url(ca_url), do: ca_url

  defp domain_params(config), do: Enum.map([config.domain | config.extra_domains], &"-d #{&1}")

  defp keys_folder(config), do: Path.join(~w(#{config_folder(config)} live #{config.domain}))
  defp config_folder(config), do: Path.join(config.base_folder, "config")
  defp log_folder(config), do: Path.join(config.base_folder, "log")
  defp work_folder(config), do: Path.join(config.base_folder, "work")
  defp webroot_folder(config), do: Path.join(config.base_folder, "webroot")

  defp keyfile(config), do: Path.join(keys_folder(config), "privkey.pem")
  defp certfile(config), do: Path.join(keys_folder(config), "cert.pem")
  defp cacertfile(config), do: Path.join(keys_folder(config), "chain.pem")

  defp keys_sha(config) do
    case pems(config) do
      :error ->
        nil

      {:ok, keys} ->
        :crypto.hash(
          :md5,
          keys |> Keyword.values() |> Enum.join()
        )
    end
  end
end
