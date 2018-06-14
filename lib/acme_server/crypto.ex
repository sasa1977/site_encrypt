defmodule AcmeServer.Crypto do
  @type id :: {integer(), integer()}

  @spec sign_csr!(id(), binary(), AcmeServer.domains()) :: binary() | no_return()
  def sign_csr!(id, csr, domains) do
    files = init_files(id)

    try do
      gen_ca_keys!(files)
      der_to_pem(files, csr)
      sign_csr(files, domains)
    after
      File.rm_rf!(files.folder)
    end
  end

  defp gen_ca_keys!(files) do
    openssl!(~w(
      req -new -newkey rsa:4096 -nodes -x509
      -subj /C=US/ST=State/L=Location/O=Org/CN=localhost
      -keyout #{files.cakey} -out #{files.cacert}
    ))
  end

  defp der_to_pem(files, csr) do
    File.write!(files.der, csr)
    openssl!(~w(req -inform der -in #{files.der} -out #{files.csr}))
  end

  defp sign_csr(files, domains) do
    File.write!(files.ext, ext_contents(domains))
    File.write!(files.caconfig, caconfig_contents(files))

    openssl!(~w(
        ca -batch -subj /CN=#{hd(domains)} -config #{files.caconfig} -extfile #{files.ext}
        -out #{files.crt} -infiles #{files.csr}
      ))

    File.read!(files.crt)
  end

  defp init_files(id) do
    folder_name = :erlang.term_to_binary(id) |> Base.url_encode64(padding: false)
    folder = Application.app_dir(:site_encrypt) |> Path.join("tmp") |> Path.join(folder_name)
    File.mkdir_p!(folder)

    [:der, :csr, :crt, :ext, :caconfig, :cakey, :cacert, :index, :serial]
    |> Enum.map(&{&1, Path.join(folder, "#{&1}")})
    |> Map.new()
    |> Map.put(:folder, folder)
  end

  defp ext_contents(domains),
    do: "subjectAltName=#{domains |> Enum.map(&"DNS:#{&1}") |> Enum.join(",")}"

  defp caconfig_contents(files) do
    File.write(files.index, "")
    File.write(files.serial, "01")

    """
    [ ca ]
    default_ca = my_ca

    [ my_ca ]
    serial = #{files.serial}
    database = #{files.index}
    new_certs_dir = #{files.folder}
    certificate = #{files.cacert}
    private_key = #{files.cakey}
    default_md = sha1
    default_days = 1
    policy = my_policy

    [ my_policy ]
    countryName = optional
    stateOrProvinceName = optional
    organizationName = optional
    commonName = optional
    organizationalUnitName = optional
    commonName = optional
    """
  end

  defp openssl!(args) do
    {_, 0} = System.cmd("openssl", args, stderr_to_stdout: true)
    :ok
  end
end
